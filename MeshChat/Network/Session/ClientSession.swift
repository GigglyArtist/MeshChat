// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import os

/// Клиентская сессия: устанавливает соединение с хостом,
/// выполняет автоматический хэндшейк, поддерживает heartbeat и переподключение (§7.6, §9).
actor ClientSession: ChatSessionManaging {

    // MARK: - nonisolated let (реализуют протокольные требования)

    nonisolated let role: SessionRole = .client
    nonisolated let events: AsyncStream<SessionEvent>

    // MARK: - Приватные поля

    private let identity: LocalIdentity
    private let invite: RoomInvite
    private let secret: any RoomSecret
    private let connector: any ClientConnecting
    private let config: NetworkConfiguration
    private let now: @Sendable () -> Date

    private var state: SessionState = .connecting
    private var continuation: AsyncStream<SessionEvent>.Continuation?
    private var connection: (any PeerConnection)?

    /// Участники, не считая хоста. Ключ — `permanentPeerID`.
    private var participants: [UUID: PeerProfile] = [:]
    /// Профиль хоста; задаётся при первом хэндшейке, используется при reconcile.
    private var storedHostProfile: PeerProfile?
    /// `sessionID` из `hostWelcome`; при переподключении сверяется для детектирования смены комнаты.
    private var currentSessionID: UUID?

    private var lastReceivedAt: ContinuousClock.Instant = ContinuousClock.now
    private var heartbeatTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    /// Задача грейс-периода или цикла переподключения (§9.2).
    private var reconnectTask: Task<Void, Never>?
    /// `ContinuousClock`-дедлайн переподключения; используется в `runReconnectLoop`.
    private var reconnectDeadline: ContinuousClock.Instant?

    private nonisolated static let logger = Logger(
        subsystem: "com.meshchat", category: "ClientSession"
    )

    // MARK: - Вспомогательные типы

    private enum ReadyResult { case ready, localNetworkDenied }
    private enum WelcomeResult { case welcome(HostWelcome), connectionClosed, timeout }

    // MARK: - Инициализация

    init(identity: LocalIdentity,
         invite: RoomInvite,
         secret: any RoomSecret,
         connector: any ClientConnecting,
         configuration: NetworkConfiguration = .standard,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.identity = identity
        self.invite = invite
        self.secret = secret
        self.connector = connector
        self.config = configuration
        self.now = now

        var cont: AsyncStream<SessionEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // MARK: - ChatSessionManaging

    nonisolated func start() async { await _start() }
    nonisolated func send(text: String) async throws -> ChatMessage { try await _send(text: text) }
    nonisolated func end() async { await _end() }

    // MARK: - Запуск

    private func _start() async {
        let conn = connector.makeConnection(serviceName: invite.serviceName,
                                           security: .tlsPSK(secret.tlsPreSharedKey))
        self.connection = conn
        conn.start()

        switch await waitForReady(conn: conn, timeout: config.connectTimeout) {
        case nil:
            transition(to: .ended(.hostUnreachable)); return
        case .localNetworkDenied:
            transition(to: .ended(.localNetworkDenied)); return
        case .ready:
            break
        }

        let hello = ClientHello(
            protocolVersion: PacketCodec.protocolVersion,
            authToken: secret.authToken(for: identity.peerID),
            permanentPeerID: identity.peerID,
            nickname: identity.nickname,
            resumeSessionID: nil
        )
        do {
            try await conn.send(.clientHello(hello))
        } catch {
            Self.logger.error("Failed to send clientHello: \(error, privacy: .public)")
            transition(to: .ended(.failed(error.localizedDescription))); return
        }

        switch await waitForWelcome(conn: conn, timeout: config.handshakeTimeout) {
        case .timeout:
            transition(to: .ended(.handshakeTimeout)); return
        case .connectionClosed:
            transition(to: .ended(.rejected)); return
        case .welcome(let w):
            guard w.status == "success" else {
                transition(to: .ended(.rejected)); return
            }

            currentSessionID = w.sessionID
            let hostProfile = PeerProfile(id: w.hostPermanentPeerID, nickname: w.hostNickname)
            storedHostProfile = hostProfile
            emit(.established(sessionID: w.sessionID))
            emit(.participantJoined(hostProfile))
            for peer in w.participants {
                let p = peer.profile
                participants[p.id] = p
                emit(.participantJoined(p))
            }
            transition(to: .active)

            startHeartbeat(conn: conn)
            startSilenceMonitor(conn: conn)
            await runPacketLoop(conn: conn)
            handleLoopExit(conn: conn)
        }
    }

    // MARK: - Основной цикл пакетов

    private func runPacketLoop(conn: any PeerConnection) async {
        for await event in conn.events {
            guard connection === conn else { break }
            switch event {
            case .packet(let pkt):
                lastReceivedAt = ContinuousClock.now
                handlePacket(pkt)

            case .viability(false), .state(.waiting):
                // Мягкий разрыв: удерживаем соединение, ждём viability=true (§9.2).
                guard case .active = state else { break }
                enterReconnecting()
                startDeadlineTask()

            case .viability(true):
                // Восстановление по soft-сигналу (§9.2).
                guard case .reconnecting = state, connection === conn else { break }
                reconnectTask?.cancel(); reconnectTask = nil
                reconnectDeadline = nil
                startHeartbeat(conn: conn)
                startSilenceMonitor(conn: conn)
                transition(to: .active)

            case .state(.cancelled), .state(.failed):
                break  // поток закроется — цикл выйдет сам

            case .protocolViolation(let e):
                Self.logger.info("Protocol violation from host: \(e, privacy: .public)")
                conn.cancel()

            default:
                break
            }
        }
    }

    // MARK: - Выход из цикла

    /// Вызывается сразу после завершения `runPacketLoop`. Определяет, нужно ли переподключаться.
    private func handleLoopExit(conn: any PeerConnection) {
        cancelHeartbeatAndSilence()
        switch state {
        case .ended:
            return
        case .active:
            // Неожиданный жёсткий разрыв, монитор тишины не успел среагировать.
            enterReconnecting()
            fallthrough
        case .reconnecting:
            startHardReconnect(conn: conn)
        case .connecting:
            break
        }
    }

    // MARK: - Переподключение (§9.2)

    private func enterReconnecting() {
        let grace = config.reconnectGracePeriod
        let (secs, attos) = grace.components
        let ti = TimeInterval(secs) + TimeInterval(attos) * 1e-18
        let deadlineDate = Date(timeIntervalSinceNow: ti)
        let clockDeadline = ContinuousClock.now + grace
        reconnectDeadline = clockDeadline
        transition(to: .reconnecting(deadline: deadlineDate))
        cancelHeartbeatAndSilence()
        Self.logger.debug("Entered reconnecting state; deadline in \(secs, privacy: .public)s")
    }

    private func startDeadlineTask() {
        let grace = config.reconnectGracePeriod
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            do { try await Task.sleep(for: grace) } catch { return }
            await self?.expireDeadline()
        }
    }

    private func expireDeadline() {
        guard case .reconnecting = state else { return }
        transition(to: .ended(.hostLost))
    }

    private func startHardReconnect(conn: any PeerConnection) {
        // Если уже идёт цикл переподключения — заменяем его на свежий.
        conn.cancel()
        if connection === conn { connection = nil }
        let deadline = reconnectDeadline ?? ContinuousClock.now
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            await self?.runReconnectLoop(deadline: deadline)
        }
    }

    private func runReconnectLoop(deadline: ContinuousClock.Instant) async {
        var attempt = 0
        let policy = ReconnectPolicy(backoff: config.reconnectBackoff)

        while ContinuousClock.now < deadline {
            guard case .reconnecting = state else { return }

            attempt += 1
            let delay = policy.delay(forAttempt: attempt)
            do { try await Task.sleep(for: delay) } catch { return }

            guard case .reconnecting = state else { return }
            guard ContinuousClock.now < deadline else { break }

            let conn = connector.makeConnection(serviceName: invite.serviceName,
                                               security: .tlsPSK(secret.tlsPreSharedKey))
            self.connection = conn
            conn.start()

            let remaining = deadline - ContinuousClock.now
            let connectTo = remaining > config.connectTimeout ? config.connectTimeout : remaining

            switch await waitForReady(conn: conn, timeout: max(connectTo, .zero)) {
            case nil:
                conn.cancel(); continue
            case .localNetworkDenied:
                transition(to: .ended(.localNetworkDenied))
                conn.cancel(); return
            case .ready:
                break
            }

            guard case .reconnecting = state else { conn.cancel(); return }

            let remaining2 = deadline - ContinuousClock.now
            let handshakeTo = remaining2 > config.handshakeTimeout ? config.handshakeTimeout : remaining2

            let hello = ClientHello(
                protocolVersion: PacketCodec.protocolVersion,
                authToken: secret.authToken(for: identity.peerID),
                permanentPeerID: identity.peerID,
                nickname: identity.nickname,
                resumeSessionID: currentSessionID
            )
            do {
                try await conn.send(.clientHello(hello))
            } catch {
                conn.cancel(); continue
            }

            guard case .reconnecting = state else { conn.cancel(); return }

            switch await waitForWelcome(conn: conn, timeout: max(handshakeTo, .zero)) {
            case .timeout, .connectionClosed:
                conn.cancel(); continue
            case .welcome(let w):
                guard case .reconnecting = state else { conn.cancel(); return }

                if w.sessionID != currentSessionID {
                    // Хост запустил новую сессию — комната сменилась.
                    Self.logger.info("Resume failed: session ID mismatch; ending with hostLost")
                    transition(to: .ended(.hostLost))
                    conn.cancel(); return
                }

                // Успешное резюме.
                reconnectDeadline = nil
                reconcileParticipants(from: w)
                transition(to: .active)
                startHeartbeat(conn: conn)
                startSilenceMonitor(conn: conn)

                await runPacketLoop(conn: conn)
                handleLoopExit(conn: conn)
                return
            }
        }

        guard case .reconnecting = state else { return }
        transition(to: .ended(.hostLost))
    }

    // MARK: - Сверка участников при резюме (§9.2 п. 4)

    private func reconcileParticipants(from welcome: HostWelcome) {
        var expected: [UUID: PeerProfile] = [:]
        for peer in welcome.participants {
            let p = peer.profile
            expected[p.id] = p
        }
        // Участники, покинувшие комнату во время обрыва.
        for (id, p) in participants where expected[id] == nil {
            participants.removeValue(forKey: id)
            emit(.participantLeft(p, .connectionLost))
        }
        // Участники, вошедшие во время обрыва.
        for (id, p) in expected where participants[id] == nil {
            participants[id] = p
            emit(.participantJoined(p))
        }
    }

    // MARK: - Heartbeat и монитор тишины (§9.6)

    private func startHeartbeat(conn: any PeerConnection) {
        heartbeatTask?.cancel()
        let interval = config.heartbeatInterval
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.sendPing(conn: conn)
            }
        }
    }

    private func sendPing(conn: any PeerConnection) async {
        guard case .active = state, connection === conn else { return }
        do {
            try await conn.send(.ping(HeartbeatPayload(sentAt: now())))
        } catch {
            Self.logger.debug("Failed to send ping: \(error, privacy: .public)")
        }
    }

    private func startSilenceMonitor(conn: any PeerConnection) {
        silenceTask?.cancel()
        let interval = config.heartbeatInterval
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.checkSilence(conn: conn)
            }
        }
    }

    private func checkSilence(conn: any PeerConnection) {
        guard case .active = state,
              connection === conn,
              ContinuousClock.now - lastReceivedAt > config.silenceTimeout else { return }
        Self.logger.debug("Silence from host detected; cancelling connection")
        conn.cancel()
        // handleLoopExit вызовется, когда runPacketLoop увидит закрытый поток.
    }

    private func cancelHeartbeatAndSilence() {
        heartbeatTask?.cancel(); heartbeatTask = nil
        silenceTask?.cancel(); silenceTask = nil
    }

    // MARK: - Ожидание .ready

    private func waitForReady(conn: any PeerConnection, timeout: Duration) async -> ReadyResult? {
        return await withTaskGroup(of: ReadyResult?.self) { group in
            group.addTask {
                for await event in conn.events {
                    switch event {
                    case .state(.ready):
                        return .ready
                    case .state(.waiting(.localNetworkDenied)):
                        return .localNetworkDenied
                    case .state(.cancelled), .state(.failed):
                        return nil
                    default:
                        break
                    }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: - Ожидание hostWelcome

    private func waitForWelcome(conn: any PeerConnection, timeout: Duration) async -> WelcomeResult {
        let inner: HostWelcome?? = await withTaskGroup(of: HostWelcome??.self) { group in
            group.addTask {
                for await event in conn.events {
                    switch event {
                    case .packet(.hostWelcome(let w)):
                        return .some(w)
                    case .state(.cancelled), .state(.failed), .protocolViolation:
                        return .some(nil)
                    default:
                        break
                    }
                }
                return .some(nil)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let r = await group.next() ?? nil
            group.cancelAll()
            return r
        }
        switch inner {
        case .none:               return .timeout
        case .some(.none):        return .connectionClosed
        case .some(.some(let w)): return .welcome(w)
        }
    }

    // MARK: - Обработка входящих пакетов

    private func handlePacket(_ packet: Packet) {
        switch packet {
        case .chatMessage(let msg):
            guard MessageTextPolicy.normalize(msg.text) != nil else {
                Self.logger.info("Received chatMessage with invalid text from host")
                return
            }
            let chatMsg = ChatMessage(id: msg.messageID, text: msg.text,
                                      timestamp: msg.timestamp, senderID: msg.senderID)
            emit(.messageReceived(chatMsg))

        case .participantJoined(let payload):
            let profile = payload.profile
            participants[profile.id] = profile
            emit(.participantJoined(profile))

        case .participantLeft(let payload):
            let id = payload.permanentPeerID
            let profile = participants.removeValue(forKey: id)
                ?? PeerProfile(id: id, nickname: "")
            emit(.participantLeft(profile, payload.leaveReason))

        case .sessionEnded:
            cancelHeartbeatAndSilence()
            reconnectTask?.cancel(); reconnectTask = nil
            transition(to: .ended(.hostEnded))
            connection?.cancel()

        case .pong:
            // lastReceivedAt уже обновлён в runPacketLoop; pong не порождает события.
            break

        case .clientHello, .leave:
            Self.logger.error("Host sent unexpected packet type")
            connection?.cancel()
            transition(to: .ended(.failed("unexpected packet from host")))

        default:
            Self.logger.info("Ignoring unknown packet type from host")
        }
    }

    // MARK: - Отправка сообщения

    private func _send(text: String) async throws -> ChatMessage {
        guard case .active = state, let conn = connection else { throw NetworkError.notActive }
        guard let normalized = MessageTextPolicy.normalize(text) else {
            throw NetworkError.invalidMessage
        }
        let msg = ChatMessage(
            id: UUID(),
            text: normalized,
            timestamp: now().flooredToMilliseconds,
            senderID: identity.peerID
        )
        try await conn.send(.chatMessage(MessagePayload(msg)))
        return msg
    }

    // MARK: - Завершение сессии

    private func _end() async {
        cancelHeartbeatAndSilence()
        reconnectTask?.cancel(); reconnectTask = nil
        switch state {
        case .active:
            let conn = connection
            connection = nil
            transition(to: .ended(.leftByUser))
            if let conn {
                do { try await conn.send(.leave) } catch {
                    Self.logger.error("Failed to send leave: \(error, privacy: .public)")
                }
                conn.cancel()
            }
        case .reconnecting:
            connection?.cancel(); connection = nil
            transition(to: .ended(.leftByUser))
        default:
            break
        }
    }

    // MARK: - Вспомогательные методы

    private func transition(to newState: SessionState) {
        state = newState
        emit(.stateChanged(newState))
        if case .ended = newState {
            continuation?.finish()
            continuation = nil
        }
    }

    private func emit(_ event: SessionEvent) {
        _ = continuation?.yield(event)
    }
}

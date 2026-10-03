// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import os

/// Хост-сессия: публикует Bonjour-сервис, принимает до 4 клиентов,
/// выполняет хэндшейк и ретранслирует сообщения (§7.5).
actor HostSession: HostSessionManaging {

    // MARK: - nonisolated let (реализуют протокольные требования через let)

    nonisolated let role: SessionRole = .host
    nonisolated let events: AsyncStream<SessionEvent>
    nonisolated let sessionID: UUID
    nonisolated let invite: RoomInvite

    // MARK: - Приватные поля

    private let identity: LocalIdentity
    private let secret: any RoomSecret
    private let listener: any HostListening
    private let config: NetworkConfiguration
    private let now: @Sendable () -> Date

    private var state: SessionState = .connecting
    private var continuation: AsyncStream<SessionEvent>.Continuation?
    /// Фоновая задача цикла перезапуска listener'а (ADR-11).
    private var listenerRestartTask: Task<Void, Never>?

    /// Авторизованные участники: peerID → слот. Suspended-участники занимают место
    /// в лимите и ждут резюма до истечения reconnectGracePeriod (§9.3).
    private var participants: [UUID: ParticipantSlot] = [:]

    private nonisolated static let logger = Logger(
        subsystem: "com.meshchat", category: "HostSession"
    )

    // MARK: - Вспомогательный тип

    private struct ParticipantSlot {
        let conn: any PeerConnection
        let profile: PeerProfile
        /// `true` пока участник временно недоступен; рассылка ему прекращена.
        var isSuspended: Bool = false
        /// Задача грейс-таймера (активна только пока `isSuspended`).
        var graceTask: Task<Void, Never>?
        /// Задача мониторинга тишины (активна пока участник не suspended).
        var silenceTask: Task<Void, Never>?
        /// Время последнего входящего пакета любого типа (§9.6).
        var lastReceivedAt: ContinuousClock.Instant = ContinuousClock.now
        /// Инкрементируется при каждом старте нового грейс-таймера;
        /// позволяет expireGrace отвергнуть вызовы от старых задач.
        var graceGeneration: Int = 0
    }

    // MARK: - Инициализация

    init(identity: LocalIdentity,
         secret: any RoomSecret,
         listener: any HostListening,
         configuration: NetworkConfiguration = .standard,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.identity = identity
        self.secret = secret
        self.listener = listener
        self.config = configuration
        self.now = now

        let sid = UUID()
        let svcName = UUID().uuidString
        self.sessionID = sid
        self.invite = RoomInvite(version: RoomInvite.currentVersion,
                                 serviceName: svcName,
                                 roomKey: secret.roomKeyData)

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
        let listenerStream: AsyncStream<ListenerEvent>
        do {
            listenerStream = try listener.start(
                serviceName: invite.serviceName,
                security: .tlsPSK(secret.tlsPreSharedKey)
            )
        } catch {
            Self.logger.error("Listener failed to start: \(error, privacy: .public)")
            transition(to: .ended(.failed(error.localizedDescription)))
            return
        }

        let needsRestart = await processListenerStream(listenerStream)
        if needsRestart { startListenerRestart(skipFirstPause: false) }
    }

    // MARK: - Поток событий listener'а

    /// Читает события listener'а; возвращает `true` если listener упал после `.active`
    /// и требуется перезапуск (ADR-11).
    private func processListenerStream(_ stream: AsyncStream<ListenerEvent>) async -> Bool {
        var readyReceived = false
        for await event in stream {
            guard !Task.isCancelled else { return false }
            switch event {
            case .ready:
                readyReceived = true
                // Переходим в .active только на первом запуске (state == .connecting).
                if case .connecting = state { transition(to: .active) }

            case .failed(let issue):
                if !readyReceived {
                    let reason: SessionEndReason = issue == .localNetworkDenied
                        ? .localNetworkDenied : .failed(issue.description)
                    transition(to: .ended(reason))
                    return false
                }
                // Упал после активной фазы.
                if issue == .localNetworkDenied {
                    transition(to: .ended(.localNetworkDenied))
                    return false
                }
                Self.logger.info("Listener failed after active (\(issue.description, privacy: .public)), scheduling restart")
                return true

            case .incoming(let conn):
                // Task наследует контекст актора — handleIncoming изолирована на этом акторе.
                Task { [weak self] in
                    guard let self else { conn.cancel(); return }
                    await self.handleIncoming(conn)
                }
            }
        }
        return false
    }

    // MARK: - Цикл перезапуска listener'а (ADR-11)

    private func startListenerRestart(skipFirstPause: Bool) {
        listenerRestartTask?.cancel()
        listenerRestartTask = Task { [weak self] in
            await self?.runListenerRestartLoop(skipFirstPause: skipFirstPause)
        }
    }

    private func runListenerRestartLoop(skipFirstPause: Bool) async {
        let policy = ReconnectPolicy(backoff: config.reconnectBackoff)
        var attempt = 0
        var skipPause = skipFirstPause
        while !Task.isCancelled {
            if !skipPause {
                let delay = policy.delay(forAttempt: attempt)
                do { try await Task.sleep(for: delay) } catch { return }
            }
            skipPause = false
            guard !Task.isCancelled, case .active = state else { return }
            attempt += 1

            let stream: AsyncStream<ListenerEvent>
            do {
                stream = try listener.start(
                    serviceName: invite.serviceName,
                    security: .tlsPSK(secret.tlsPreSharedKey)
                )
            } catch {
                Self.logger.error("Listener restart start() threw: \(error, privacy: .public)")
                continue
            }

            let needsRestart = await processListenerStream(stream)
            if !needsRestart { return }
        }
    }

    // MARK: - Хэндшейк входящего соединения

    private func handleIncoming(_ conn: any PeerConnection) async {
        conn.start()

        guard let hello = await waitForHello(conn: conn, timeout: config.handshakeTimeout) else {
            conn.cancel(); return
        }

        // Структурные проверки.
        guard hello.protocolVersion == PacketCodec.protocolVersion else {
            Self.logger.info("clientHello: unsupported protocolVersion \(hello.protocolVersion, privacy: .public)")
            conn.cancel(); return
        }
        guard secret.isValidAuthToken(hello.authToken, for: hello.permanentPeerID) else {
            Self.logger.info("clientHello: invalid authToken for \(hello.permanentPeerID, privacy: .private)")
            conn.cancel(); return
        }
        guard let normalizedNick = NicknamePolicy.normalize(hello.nickname) else {
            Self.logger.info("clientHello: invalid nickname")
            conn.cancel(); return
        }
        guard hello.permanentPeerID != identity.peerID else {
            Self.logger.info("clientHello: peer ID matches host ID")
            conn.cancel(); return
        }

        // После await: перепроверить, что сессия ещё активна.
        guard case .active = state else { conn.cancel(); return }

        let peerID = hello.permanentPeerID
        let profile = PeerProfile(id: peerID, nickname: normalizedNick)

        let isRejoining: Bool
        let isResume: Bool
        if let existing = participants[peerID] {
            // Участник уже есть — отменяем задачи и закрываем старое соединение.
            existing.graceTask?.cancel()
            existing.silenceTask?.cancel()
            existing.conn.cancel()
            isResume = existing.isSuspended
            isRejoining = true
        } else {
            isResume = false
            guard participants.count < config.maxClients else {
                Self.logger.info("clientHello: room is full (\(self.participants.count, privacy: .public))")
                conn.cancel(); return
            }
            isRejoining = false
        }
        participants[peerID] = ParticipantSlot(conn: conn, profile: profile)

        // Формируем список остальных участников для hostWelcome.
        let otherParticipants = participants
            .filter { $0.key != peerID }
            .map { PeerPayload($0.value.profile) }

        let welcome = HostWelcome(
            status: "success",
            sessionID: sessionID,
            hostPermanentPeerID: identity.peerID,
            hostNickname: identity.nickname,
            participants: otherParticipants
        )

        do {
            try await conn.send(.hostWelcome(welcome))
        } catch {
            Self.logger.error("Failed to send hostWelcome: \(error, privacy: .public)")
            participants.removeValue(forKey: peerID)
            conn.cancel(); return
        }

        // После await: убедиться, что это соединение не было вытеснено.
        guard participants[peerID]?.conn === conn else { return }

        if isResume {
            Self.logger.info("Participant \(peerID, privacy: .private) resumed session (§9.3)")
        } else if !isRejoining {
            emit(.participantJoined(profile))
            await relay(.participantJoined(PeerPayload(profile)), excluding: peerID)
        }

        startSilenceMonitor(for: peerID, conn: conn)
        await runPacketLoop(conn: conn, peerID: peerID, profile: profile)
    }

    // MARK: - Ожидание clientHello (с таймаутом)

    private func waitForHello(conn: any PeerConnection, timeout: Duration) async -> ClientHello? {
        return await withTaskGroup(of: ClientHello?.self) { group in
            group.addTask {
                var readyReceived = false
                var bufferedHello: ClientHello? = nil
                for await event in conn.events {
                    switch event {
                    case .state(.ready):
                        readyReceived = true
                        if let h = bufferedHello { return h }
                    case .state(.cancelled), .state(.failed):
                        return nil
                    case .packet(let pkt):
                        if case .clientHello(let h) = pkt {
                            if readyReceived { return h }
                            bufferedHello = h
                        } else {
                            return nil
                        }
                    case .protocolViolation:
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

    // MARK: - Монитор тишины (§9.6)

    private func startSilenceMonitor(for peerID: UUID, conn: any PeerConnection) {
        let interval = config.heartbeatInterval
        let silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.checkSilence(for: peerID, conn: conn)
            }
        }
        if var slot = participants[peerID], slot.conn === conn {
            slot.silenceTask?.cancel()
            slot.silenceTask = silenceTask
            participants[peerID] = slot
        }
    }

    private func checkSilence(for peerID: UUID, conn: any PeerConnection) {
        guard let slot = participants[peerID],
              slot.conn === conn,
              !slot.isSuspended else { return }
        let elapsed = ContinuousClock.now - slot.lastReceivedAt
        guard elapsed > config.silenceTimeout else { return }
        Self.logger.debug("Silence detected for \(peerID, privacy: .private)")
        conn.cancel()
        suspendParticipant(peerID, conn: conn)
    }

    // MARK: - Основной цикл пакетов авторизованного клиента

    private func runPacketLoop(conn: any PeerConnection, peerID: UUID, profile: PeerProfile) async {
        for await event in conn.events {
            guard participants[peerID]?.conn === conn else { break }

            switch event {
            case .packet(let pkt):
                // Любой входящий пакет обновляет таймер тишины (§9.6).
                if var slot = participants[peerID], slot.conn === conn {
                    slot.lastReceivedAt = ContinuousClock.now
                    if slot.isSuspended {
                        // Пакет при suspended — признак восстановления (§9.3).
                        slot.graceTask?.cancel()
                        slot.graceTask = nil
                        slot.isSuspended = false
                        participants[peerID] = slot
                        startSilenceMonitor(for: peerID, conn: conn)
                        Self.logger.debug("Participant \(peerID, privacy: .private) resumed via packet")
                    } else {
                        participants[peerID] = slot
                    }
                }
                guard participants[peerID]?.conn === conn,
                      participants[peerID]?.isSuspended == false else { break }
                await handleAuthorizedPacket(pkt, from: peerID, conn: conn, profile: profile)

            case .viability(false), .state(.waiting):
                // Мягкий разрыв — переводим в suspended, ждём восстановления (§9.3).
                suspendParticipant(peerID, conn: conn)

            case .viability(true):
                // Восстановление пути на том же соединении.
                resumeViability(peerID, conn: conn)

            case .state(.cancelled), .state(.failed):
                break

            case .protocolViolation(let e):
                Self.logger.info("Protocol violation from \(peerID, privacy: .private): \(e, privacy: .public)")
                conn.cancel()

            default:
                break
            }
        }

        // Поток закрылся — подвешиваем участника, если ещё активен.
        guard participants[peerID]?.conn === conn else { return }
        suspendParticipant(peerID, conn: conn)
    }

    // MARK: - Подвеска / возобновление (§9.3)

    private func suspendParticipant(_ peerID: UUID, conn: any PeerConnection) {
        guard var slot = participants[peerID],
              slot.conn === conn,
              !slot.isSuspended else { return }
        slot.isSuspended = true
        slot.silenceTask?.cancel()
        slot.silenceTask = nil
        slot.graceTask?.cancel()
        slot.graceGeneration += 1
        let gen = slot.graceGeneration
        let gracePeriod = config.reconnectGracePeriod
        slot.graceTask = Task { [weak self] in
            do { try await Task.sleep(for: gracePeriod) } catch { return }
            await self?.expireGrace(for: peerID, conn: conn, generation: gen)
        }
        participants[peerID] = slot
        Self.logger.debug("Participant \(peerID, privacy: .private) suspended")
    }

    /// Восстанавливает участника по сигналу `viability(true)` (соединение то же).
    private func resumeViability(_ peerID: UUID, conn: any PeerConnection) {
        guard var slot = participants[peerID],
              slot.conn === conn,
              slot.isSuspended else { return }
        slot.graceTask?.cancel()
        slot.graceTask = nil
        slot.isSuspended = false
        slot.lastReceivedAt = ContinuousClock.now
        participants[peerID] = slot
        startSilenceMonitor(for: peerID, conn: conn)
        Self.logger.debug("Participant \(peerID, privacy: .private) resumed via viability")
    }

    private func expireGrace(for peerID: UUID, conn: any PeerConnection, generation: Int) {
        guard let slot = participants[peerID],
              slot.conn === conn,
              slot.isSuspended,
              slot.graceGeneration == generation else { return }
        participants.removeValue(forKey: peerID)
        emit(.participantLeft(slot.profile, .connectionLost))
        Task { [weak self] in
            await self?.relay(
                .participantLeft(ParticipantLeftPayload(peerID: peerID, reason: .connectionLost)),
                excluding: peerID
            )
        }
        Self.logger.info("Grace expired for \(peerID, privacy: .private): participantLeft(.connectionLost)")
    }

    // MARK: - Обработка пакетов авторизованного клиента

    private func handleAuthorizedPacket(
        _ packet: Packet,
        from peerID: UUID,
        conn: any PeerConnection,
        profile: PeerProfile
    ) async {
        switch packet {
        case .ping(let payload):
            // Немедленный pong; ping/pong не выдают событий наружу (§9.6).
            do {
                try await conn.send(.pong(payload))
            } catch {
                Self.logger.debug("Failed to send pong to \(peerID, privacy: .private): \(error, privacy: .public)")
            }

        case .chatMessage(let msg):
            guard msg.senderID == peerID else {
                Self.logger.info("chatMessage senderID mismatch from \(peerID, privacy: .private)")
                conn.cancel(); return
            }
            guard MessageTextPolicy.normalize(msg.text) != nil else {
                Self.logger.info("chatMessage text failed policy from \(peerID, privacy: .private)")
                return
            }
            let chatMsg = ChatMessage(id: msg.messageID, text: msg.text,
                                      timestamp: msg.timestamp, senderID: msg.senderID)
            emit(.messageReceived(chatMsg))
            await relay(packet, excluding: peerID)

        case .leave:
            let slot = participants.removeValue(forKey: peerID)
            slot?.silenceTask?.cancel()
            slot?.graceTask?.cancel()
            conn.cancel()
            emit(.participantLeft(profile, .left))
            await relay(.participantLeft(ParticipantLeftPayload(peerID: peerID, reason: .left)),
                        excluding: peerID)

        case .clientHello:
            // Повторный clientHello на авторизованном соединении — нарушение протокола.
            Self.logger.info("Duplicate clientHello from \(peerID, privacy: .private)")
            conn.cancel()

        default:
            Self.logger.info("Unexpected packet from \(peerID, privacy: .private): ignored")
        }
    }

    // MARK: - Отправка своего сообщения

    private func _send(text: String) async throws -> ChatMessage {
        guard case .active = state else { throw NetworkError.notActive }
        guard let normalized = MessageTextPolicy.normalize(text) else {
            throw NetworkError.invalidMessage
        }
        let msg = ChatMessage(
            id: UUID(),
            text: normalized,
            timestamp: now().flooredToMilliseconds,
            senderID: identity.peerID
        )
        emit(.messageReceived(msg))
        await relay(.chatMessage(MessagePayload(msg)), excluding: nil)
        return msg
    }

    // MARK: - Завершение сессии

    private func _end() async {
        guard case .active = state else { return }
        listenerRestartTask?.cancel()
        listenerRestartTask = nil
        transition(to: .ended(.leftByUser))
        await broadcastSessionEnded()
        try? await Task.sleep(for: config.sessionEndFlushTimeout)
        cancelAllParticipants()
        listener.stop()
    }

    private func broadcastSessionEnded() async {
        let payload = SessionEndedPayload(reason: "hostClosed")
        for slot in participants.values {
            do {
                try await slot.conn.send(.sessionEnded(payload))
            } catch {
                Self.logger.error("Failed to send sessionEnded: \(error, privacy: .public)")
            }
        }
    }

    private func cancelAllParticipants() {
        let slots = Array(participants.values)
        participants.removeAll()
        for slot in slots {
            slot.graceTask?.cancel()
            slot.silenceTask?.cancel()
            slot.conn.cancel()
        }
    }

    // MARK: - Ретрансляция

    /// Пересылает `packet` всем **активным** (не suspended) участникам, кроме `excludeID`.
    private func relay(_ packet: Packet, excluding excludeID: UUID?) async {
        let targets = participants
            .filter { $0.key != excludeID && !$0.value.isSuspended }
            .map { $0.value.conn }
        for conn in targets {
            do {
                try await conn.send(packet)
            } catch {
                Self.logger.error("Relay send failed: \(error, privacy: .public)")
            }
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

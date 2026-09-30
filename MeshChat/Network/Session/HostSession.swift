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

    /// Авторизованные участники: peerID → (соединение, профиль).
    private var participants: [UUID: ParticipantSlot] = [:]

    private nonisolated static let logger = Logger(
        subsystem: "com.meshchat", category: "HostSession"
    )

    // MARK: - Вспомогательный тип

    private struct ParticipantSlot {
        let conn: any PeerConnection
        let profile: PeerProfile
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

        // Обрабатываем события listener'а; входящие соединения запускаем параллельно.
        for await event in listenerStream {
            switch event {
            case .ready:
                transition(to: .active)

            case .failed(let issue):
                let reason: SessionEndReason = issue == .localNetworkDenied
                    ? .localNetworkDenied : .failed(issue.description)
                transition(to: .ended(reason))
                return

            case .incoming(let conn):
                // Task наследует контекст актора — handleIncoming изолирована на этом акторе.
                Task { [weak self] in
                    guard let self else { conn.cancel(); return }
                    await self.handleIncoming(conn)
                }
            }
        }
    }

    // MARK: - Хэндшейк входящего соединения

    private func handleIncoming(_ conn: any PeerConnection) async {
        conn.start()

        // Ждать .ready и первый пакет в рамках handshakeTimeout.
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

        // Повторный вход того же участника.
        let isRejoining: Bool
        if let existing = participants[peerID] {
            existing.conn.cancel()
            participants[peerID] = ParticipantSlot(conn: conn, profile: profile)
            isRejoining = true
        } else {
            guard participants.count < config.maxClients else {
                Self.logger.info("clientHello: room is full (\(self.participants.count, privacy: .public))")
                conn.cancel(); return
            }
            participants[peerID] = ParticipantSlot(conn: conn, profile: profile)
            isRejoining = false
        }

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

        if !isRejoining {
            emit(.participantJoined(profile))
            await relay(.participantJoined(PeerPayload(profile)), excluding: peerID)
        }

        await runPacketLoop(conn: conn, peerID: peerID, profile: profile)
    }

    // MARK: - Ожидание clientHello (с таймаутом)

    private func waitForHello(conn: any PeerConnection, timeout: Duration) async -> ClientHello? {
        // Используем withTaskGroup для встроенного таймаута.
        return await withTaskGroup(of: ClientHello?.self) { group in
            group.addTask {
                var readyReceived = false
                var bufferedHello: ClientHello? = nil
                for await event in conn.events {
                    switch event {
                    case .state(.ready):
                        readyReceived = true
                        // clientHello мог прийти раньше .ready — возвращаем его.
                        if let h = bufferedHello { return h }
                    case .state(.cancelled), .state(.failed):
                        return nil
                    case .packet(let pkt):
                        if case .clientHello(let h) = pkt {
                            if readyReceived { return h }
                            // В фейке пакет может прийти до .ready — буферизуем.
                            bufferedHello = h
                        } else {
                            // Любой другой пакет до хэндшейка — нарушение протокола.
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
            // Первый результат (хэндшейк или таймаут) определяет исход.
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: - Основной цикл пакетов авторизованного клиента

    private func runPacketLoop(conn: any PeerConnection, peerID: UUID, profile: PeerProfile) async {
        for await event in conn.events {
            // Перепроверяем актуальность соединения после каждого await.
            guard participants[peerID]?.conn === conn else { break }

            switch event {
            case .packet(let pkt):
                await handleAuthorizedPacket(pkt, from: peerID, conn: conn, profile: profile)
            case .state(.cancelled), .state(.failed):
                break
            case .protocolViolation(let e):
                Self.logger.info("Protocol violation from \(peerID, privacy: .private): \(e, privacy: .public)")
                conn.cancel()
            default:
                break
            }
        }

        // Соединение закрылось.
        guard participants[peerID]?.conn === conn else { return }
        participants.removeValue(forKey: peerID)
        emit(.participantLeft(profile, .connectionLost))
        await relay(.participantLeft(ParticipantLeftPayload(peerID: peerID, reason: .connectionLost)),
                    excluding: peerID)
    }

    private func handleAuthorizedPacket(
        _ packet: Packet,
        from peerID: UUID,
        conn: any PeerConnection,
        profile: PeerProfile
    ) async {
        switch packet {
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
            participants.removeValue(forKey: peerID)
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
        slots.forEach { $0.conn.cancel() }
    }

    // MARK: - Ретрансляция

    /// Пересылает `packet` всем участникам, кроме `excludeID`. `nil` — рассылка всем.
    private func relay(_ packet: Packet, excluding excludeID: UUID?) async {
        let targets = participants
            .filter { $0.key != excludeID }
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
        continuation?.yield(event)
    }
}

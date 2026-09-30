// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import os

/// Клиентская сессия: устанавливает соединение с хостом,
/// выполняет автоматический хэндшейк и обрабатывает входящие пакеты (§7.6).
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
    private var participants: [UUID: PeerProfile] = [:]

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

        // Ждать .ready.
        let readyResult = await waitForReady(conn: conn, timeout: config.connectTimeout)
        switch readyResult {
        case nil:
            transition(to: .ended(.hostUnreachable)); return
        case .localNetworkDenied:
            transition(to: .ended(.localNetworkDenied)); return
        case .ready:
            break
        }

        // Автоматически отправить clientHello.
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

        // Ждать hostWelcome.
        switch await waitForWelcome(conn: conn, timeout: config.handshakeTimeout) {
        case .timeout:
            transition(to: .ended(.handshakeTimeout)); return
        case .connectionClosed:
            transition(to: .ended(.rejected)); return
        case .welcome(let w):
            guard w.status == "success" else {
                transition(to: .ended(.rejected)); return
            }
            let welcome = w

            emit(.established(sessionID: welcome.sessionID))
            let hostProfile = PeerProfile(id: welcome.hostPermanentPeerID,
                                          nickname: welcome.hostNickname)
            emit(.participantJoined(hostProfile))
            for peer in welcome.participants {
                let profile = peer.profile
                participants[profile.id] = profile
                emit(.participantJoined(profile))
            }
            transition(to: .active)
            await runPacketLoop(conn: conn, hostProfile: hostProfile)
        }
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
        // Используем Optional<HostWelcome?> для разделения:
        // .some(.some(w)) → получен welcome
        // .some(nil)       → соединение закрыто
        // nil              → таймаут
        let inner: HostWelcome?? = await withTaskGroup(of: HostWelcome??.self) { group in
            group.addTask {
                for await event in conn.events {
                    switch event {
                    case .packet(.hostWelcome(let w)):
                        return .some(w)          // .some(.some(w))
                    case .state(.cancelled), .state(.failed), .protocolViolation:
                        return .some(nil)         // .some(nil) — закрыто
                    default:
                        break
                    }
                }
                return .some(nil)  // поток закончился
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil          // nil — таймаут
            }
            let r = await group.next() ?? nil
            group.cancelAll()
            return r
        }
        switch inner {
        case .none:                      return .timeout
        case .some(.none):               return .connectionClosed
        case .some(.some(let w)):        return .welcome(w)
        }
    }

    // MARK: - Основной цикл пакетов

    private func runPacketLoop(conn: any PeerConnection, hostProfile: PeerProfile) async {
        for await event in conn.events {
            guard connection === conn else { break }
            switch event {
            case .packet(let pkt):
                handlePacket(pkt)
            case .state(.cancelled), .state(.failed):
                break
            case .protocolViolation(let e):
                Self.logger.info("Protocol violation from host: \(e, privacy: .public)")
                conn.cancel()
            default:
                break
            }
        }

        guard case .active = state else { return }
        transition(to: .ended(.hostLost))
    }

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
            transition(to: .ended(.hostEnded))
            connection?.cancel()

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
        guard case .active = state, let conn = connection else { return }
        transition(to: .ended(.leftByUser))
        do {
            try await conn.send(.leave)
        } catch {
            Self.logger.error("Failed to send leave: \(error, privacy: .public)")
        }
        conn.cancel()
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

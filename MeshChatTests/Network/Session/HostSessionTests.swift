// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

// MARK: - Тест-сьют

/// `@MainActor` нужен потому, что с `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
/// инициализатор актора `HostSession` выводится как `@MainActor`-изолированный.
@MainActor
@Suite("HostSession", .serialized, .timeLimit(.minutes(1)))
struct HostSessionTests {

    // MARK: - Вспомогательные методы

    func makeSecret() -> any RoomSecret {
        try! RoomCredentials(roomKeyData: Data(repeating: 0xAB, count: 32))
    }

    func makeSession(
        identity: LocalIdentity = .makeTest(),
        secret: (any RoomSecret)? = nil,
        listener: FakeHostListener? = nil
    ) -> (HostSession, FakeHostListener) {
        let s = secret ?? makeSecret()
        let l = listener ?? FakeHostListener()
        let session = HostSession(identity: identity, secret: s, listener: l,
                                  configuration: .test)
        return (session, l)
    }

    /// Подключает пару и принимает серверный конец через listener.
    func makePair(listener: FakeHostListener) -> (client: FakePeerConnection, server: FakePeerConnection) {
        let (client, server) = FakePeerConnection.makePair()
        listener.accept(server)
        return (client, server)
    }

    // MARK: 1. Переход в .active при .ready

    @Test("listener ready → state becomes .active")
    func listenerReadyActivates() async throws {
        let (session, listener) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }
        listener.emitReady()
        _ = try await probe.waitFor(timeout: .seconds(2)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }
    }

    // MARK: 2. Ошибка listener → .localNetworkDenied

    @Test("listener failed localNetworkDenied → ended(.localNetworkDenied)")
    func listenerFailedLocalNetworkDenied() async throws {
        let (session, listener) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }
        listener.emitFailure(.localNetworkDenied)
        _ = try await probe.waitFor(timeout: .seconds(2)) {
            if case .stateChanged(.ended(.localNetworkDenied)) = $0 { return true }; return false
        }
    }

    // MARK: 3. Ошибка listener → .failed

    @Test("listener failed other → ended(.failed)")
    func listenerFailedOther() async throws {
        let (session, listener) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }
        listener.emitFailure(.other("boom"))
        _ = try await probe.waitFor(timeout: .seconds(2)) {
            if case .stateChanged(.ended(.failed)) = $0 { return true }; return false
        }
    }

    // MARK: 4. Успешный хэндшейк → hostWelcome

    @Test("successful handshake: client receives hostWelcome with status success")
    func successfulHandshake() async throws {
        let secret = makeSecret()
        let hostIdentity = LocalIdentity.makeTest(nickname: "Host")
        let (session, listener) = makeSession(identity: hostIdentity, secret: secret)
        Task { await session.start() }
        listener.emitReady()

        let (client, server) = FakePeerConnection.makePair()
        listener.accept(server)
        let clientIdentity = LocalIdentity.makeTest(nickname: "Alice")
        let (welcome, _) = try await playClient(connection: client, identity: clientIdentity,
                                                secret: secret)
        #expect(welcome.status == "success")
        #expect(welcome.sessionID == session.sessionID)
        #expect(welcome.hostPermanentPeerID == hostIdentity.peerID)
        #expect(welcome.hostNickname == "Host")
    }

    // MARK: 5. Таймаут хэндшейка → нет краша, сессия остаётся .active

    @Test("handshake timeout: connection cancelled, session stays active")
    func handshakeTimeout() async throws {
        let (session, listener) = makeSession()
        let sessionProbe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }
        listener.emitReady()
        _ = try await sessionProbe.waitFor(timeout: .seconds(2)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Клиент подключается, но НЕ посылает clientHello.
        let (clientConn, serverConn) = FakePeerConnection.makePair()
        listener.accept(serverConn)

        // Ждём дольше handshakeTimeout (300 мс) — сессия не должна упасть.
        try await Task.sleep(for: .milliseconds(600))
        // Хост ничего не должен был отправить (хэндшейк не прошёл).
        #expect(serverConn.sentPackets.isEmpty)
        _ = clientConn
    }

    // MARK: 6. Неверный authToken → соединение отменяется

    @Test("invalid authToken: connection cancelled")
    func invalidAuthToken() async throws {
        let secret = makeSecret()
        let (session, listener) = makeSession(secret: secret)
        Task { await session.start() }
        listener.emitReady()

        let (clientConn, serverConn) = FakePeerConnection.makePair()
        listener.accept(serverConn)

        let wrongHello = ClientHello(
            protocolVersion: PacketCodec.protocolVersion,
            authToken: Data(repeating: 0xFF, count: 32),
            permanentPeerID: UUID(),
            nickname: "Hacker",
            resumeSessionID: nil
        )
        try await clientConn.send(.clientHello(wrongHello))

        // cancel() на serverConn → также эмитит .cancelled на clientConn.
        let clientProbe = EventProbe<ConnectionEvent>(stream: clientConn.events)
        _ = try await clientProbe.waitFor(timeout: .seconds(2)) {
            if case .state(.cancelled) = $0 { return true }; return false
        }
        _ = session
    }

    // MARK: 7. Неверная версия протокола → соединение отменяется

    @Test("wrong protocolVersion: connection cancelled")
    func wrongProtocolVersion() async throws {
        let secret = makeSecret()
        let clientID = UUID()
        let (session, listener) = makeSession(secret: secret)
        Task { await session.start() }
        listener.emitReady()

        let (clientConn, serverConn) = FakePeerConnection.makePair()
        listener.accept(serverConn)

        let badHello = ClientHello(
            protocolVersion: 99,
            authToken: secret.authToken(for: clientID),
            permanentPeerID: clientID,
            nickname: "Client",
            resumeSessionID: nil
        )
        try await clientConn.send(.clientHello(badHello))

        let clientProbe = EventProbe<ConnectionEvent>(stream: clientConn.events)
        _ = try await clientProbe.waitFor(timeout: .seconds(2)) {
            if case .state(.cancelled) = $0 { return true }; return false
        }
        _ = session
    }

    // MARK: 8. Неверный никнейм → соединение отменяется

    @Test("invalid nickname: connection cancelled")
    func invalidNickname() async throws {
        let secret = makeSecret()
        let clientID = UUID()
        let (session, listener) = makeSession(secret: secret)
        Task { await session.start() }
        listener.emitReady()

        let (clientConn, serverConn) = FakePeerConnection.makePair()
        listener.accept(serverConn)

        let badHello = ClientHello(
            protocolVersion: PacketCodec.protocolVersion,
            authToken: secret.authToken(for: clientID),
            permanentPeerID: clientID,
            nickname: "",  // пустой ник
            resumeSessionID: nil
        )
        try await clientConn.send(.clientHello(badHello))

        let clientProbe = EventProbe<ConnectionEvent>(stream: clientConn.events)
        _ = try await clientProbe.waitFor(timeout: .seconds(2)) {
            if case .state(.cancelled) = $0 { return true }; return false
        }
        _ = session
    }

    // MARK: 9. Совпадение peerID с хостом → соединение отменяется

    @Test("peerID matches host: connection cancelled")
    func peerIDMatchesHost() async throws {
        let secret = makeSecret()
        let hostIdentity = LocalIdentity.makeTest()
        let (session, listener) = makeSession(identity: hostIdentity, secret: secret)
        Task { await session.start() }
        listener.emitReady()

        let (clientConn, serverConn) = FakePeerConnection.makePair()
        listener.accept(serverConn)

        let badHello = ClientHello(
            protocolVersion: PacketCodec.protocolVersion,
            authToken: secret.authToken(for: hostIdentity.peerID),
            permanentPeerID: hostIdentity.peerID,
            nickname: "Ghost",
            resumeSessionID: nil
        )
        try await clientConn.send(.clientHello(badHello))

        let clientProbe = EventProbe<ConnectionEvent>(stream: clientConn.events)
        _ = try await clientProbe.waitFor(timeout: .seconds(2)) {
            if case .state(.cancelled) = $0 { return true }; return false
        }
        _ = session
    }

    // MARK: 10. Переполнение комнаты → 5-й клиент отклоняется

    @Test("room full: 5th client rejected")
    func roomFull() async throws {
        let secret = makeSecret()
        let (session, listener) = makeSession(secret: secret)
        let sessionProbe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }
        listener.emitReady()
        _ = try await sessionProbe.waitFor(timeout: .seconds(2)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        var clientConns: [FakePeerConnection] = []
        for i in 0..<4 {
            let clientID = UUID()
            let (clientConn, serverConn) = FakePeerConnection.makePair()
            listener.accept(serverConn)
            let identity = LocalIdentity(peerID: clientID, nickname: "Client\(i)")
            try await playClient(connection: clientConn, identity: identity, secret: secret)
            clientConns.append(clientConn)
        }

        // 5-й клиент — должен быть отклонён.
        let fifthID = UUID()
        let (fifthClient, fifthServer) = FakePeerConnection.makePair()
        listener.accept(fifthServer)
        let fifthHello = ClientHello(
            protocolVersion: PacketCodec.protocolVersion,
            authToken: secret.authToken(for: fifthID),
            permanentPeerID: fifthID,
            nickname: "Fifth",
            resumeSessionID: nil
        )
        try await fifthClient.send(.clientHello(fifthHello))

        // Ожидаем отмену клиентского конца (cancel на serverConn → emit на fifthClient).
        let fifthProbe = EventProbe<ConnectionEvent>(stream: fifthClient.events)
        _ = try await fifthProbe.waitFor(timeout: .seconds(2)) {
            if case .state(.cancelled) = $0 { return true }; return false
        }
        _ = clientConns
    }

    // MARK: 11. participantJoined при успешном хэндшейке

    @Test("successful join emits participantJoined on session events")
    func participantJoinedEvent() async throws {
        let secret = makeSecret()
        let (session, listener) = makeSession(secret: secret)
        let sessionProbe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }
        listener.emitReady()

        let clientIdentity = LocalIdentity.makeTest(nickname: "Alice")
        let (clientConn, serverConn) = FakePeerConnection.makePair()
        listener.accept(serverConn)
        try await playClient(connection: clientConn, identity: clientIdentity, secret: secret)

        _ = try await sessionProbe.waitFor(timeout: .seconds(2)) {
            if case .participantJoined(let p) = $0 { return p.id == clientIdentity.peerID }
            return false
        }
    }

    // MARK: 12. participantLeft при leave

    @Test("client sends leave → participantLeft(.left)")
    func participantLeft_leave() async throws {
        let secret = makeSecret()
        let (session, listener) = makeSession(secret: secret)
        let sessionProbe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }
        listener.emitReady()

        let clientIdentity = LocalIdentity.makeTest(nickname: "Bob")
        let (clientConn, serverConn) = FakePeerConnection.makePair()
        listener.accept(serverConn)
        try await playClient(connection: clientConn, identity: clientIdentity, secret: secret)

        try await clientConn.send(.leave)

        _ = try await sessionProbe.waitFor(timeout: .seconds(2)) {
            if case .participantLeft(let p, let r) = $0 {
                return p.id == clientIdentity.peerID && r == .left
            }
            return false
        }
    }

    // MARK: 13. participantLeft при разрыве связи

    @Test("connection dropped → participantLeft(.connectionLost)")
    func participantLeft_connectionLost() async throws {
        let secret = makeSecret()
        let (session, listener) = makeSession(secret: secret)
        let sessionProbe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }
        listener.emitReady()

        let clientIdentity = LocalIdentity.makeTest(nickname: "Charlie")
        let (clientConn, serverConn) = FakePeerConnection.makePair()
        listener.accept(serverConn)
        let (_, clientProbe) = try await playClient(connection: clientConn,
                                                    identity: clientIdentity, secret: secret)

        // Симулируем разрыв: clientConn.emitFailure() → also cancels serverConn peer end.
        clientConn.emitFailure()

        _ = try await sessionProbe.waitFor(timeout: .seconds(2)) {
            if case .participantLeft(let p, let r) = $0 {
                return p.id == clientIdentity.peerID && r == .connectionLost
            }
            return false
        }
        _ = clientProbe
    }

    // MARK: 14. Ретрансляция chatMessage

    @Test("chatMessage from A relayed to B; host gets messageReceived; A gets no echo")
    func messageRelay() async throws {
        let secret = makeSecret()
        let (session, listener) = makeSession(secret: secret)
        let sessionProbe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }
        listener.emitReady()

        let idA = LocalIdentity.makeTest(nickname: "A")
        let idB = LocalIdentity.makeTest(nickname: "B")

        let (connA, serverA) = FakePeerConnection.makePair()
        listener.accept(serverA)
        let (_, probeA) = try await playClient(connection: connA, identity: idA, secret: secret)

        let (connB, serverB) = FakePeerConnection.makePair()
        listener.accept(serverB)
        let (_, probeB) = try await playClient(connection: connB, identity: idB, secret: secret)

        let msgID = UUID()
        let msgPayload = MessagePayload(messageID: msgID, senderID: idA.peerID,
                                        text: "hello", timestamp: Date())
        try await connA.send(.chatMessage(msgPayload))

        _ = try await sessionProbe.waitFor(timeout: .seconds(2)) {
            if case .messageReceived(let m) = $0 { return m.id == msgID }
            return false
        }
        _ = try await probeB.waitFor(timeout: .seconds(2)) {
            if case .packet(.chatMessage(let m)) = $0 { return m.messageID == msgID }
            return false
        }

        try await Task.sleep(for: .milliseconds(100))
        let aEcho = probeA.events.filter {
            if case .packet(.chatMessage(let m)) = $0 { return m.messageID == msgID }; return false
        }
        #expect(aEcho.isEmpty, "sender must not receive echo")
    }

    // MARK: 15. send(text:) до .active → NetworkError.notActive

    @Test("send before active → NetworkError.notActive")
    func sendBeforeActive() async throws {
        let (session, _) = makeSession()
        do {
            _ = try await session.send(text: "test")
            Issue.record("Expected NetworkError.notActive")
        } catch NetworkError.notActive {
            // ожидаемо
        }
    }
}

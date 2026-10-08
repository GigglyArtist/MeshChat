// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

// MARK: - Тест-сьют

/// `@MainActor` нужен, так как `ClientSession.init` выводится как `@MainActor`-изолированный
/// при `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@MainActor
@Suite("ClientSession", .serialized, .timeLimit(.minutes(1)))
struct ClientSessionTests {

    // MARK: - Вспомогательные методы

    func makeSecret() -> any RoomSecret {
        try! RoomCredentials(roomKeyData: Data(repeating: 0xCD, count: 32))
    }

    func makeInvite(secret: any RoomSecret) -> RoomInvite {
        RoomInvite(version: RoomInvite.currentVersion,
                   serviceName: UUID().uuidString,
                   roomKey: secret.roomKeyData)
    }

    /// Создаёт `ClientSession` с вспомогательными фейками.
    ///
    /// По умолчанию используется `.loopback` (секундные таймауты), чтобы тесты успеха
    /// не зависели от задержек `@MainActor` под нагрузкой (§16.3).
    /// Тесты, которые проверяют сам таймаут, передают `.test` явно.
    func makeSession(
        identity: LocalIdentity = .makeTest(),
        secret: (any RoomSecret)? = nil,
        mode: ConnectionMode = .reachable,
        configuration: NetworkConfiguration = .loopback
    ) -> (ClientSession, FakeHostListener, FakeClientConnector) {
        let s = secret ?? makeSecret()
        let invite = makeInvite(secret: s)
        let listener = FakeHostListener()
        let connector = FakeClientConnector(listener: listener, mode: mode)
        let session = ClientSession(identity: identity, invite: invite, secret: s,
                                    connector: connector, configuration: configuration)
        return (session, listener, connector)
    }

    /// Выполняет хэндшейк до состояния `.active` и возвращает серверный конец соединения.
    @discardableResult
    func handshake(
        session: ClientSession,
        connector: FakeClientConnector,
        probe: EventProbe<SessionEvent>,
        sessionID: UUID = UUID(),
        hostID: UUID = UUID(),
        participants: [PeerPayload] = []
    ) async throws -> FakePeerConnection {
        Task { await session.start() }
        let serverConn = try await waitForServer(connector: connector)
        let welcome = HostWelcome(status: "success", sessionID: sessionID,
                                  hostPermanentPeerID: hostID, hostNickname: "Host",
                                  participants: participants)
        try await serverConn.send(.hostWelcome(welcome))
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }
        return serverConn
    }

    // MARK: 1. Успешный хэндшейк

    @Test("successful handshake → established, participantJoined(host), stateChanged(.active)")
    func successfulHandshake() async throws {
        let (session, _, connector) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)

        let sid = UUID()
        let hostID = UUID()
        try await handshake(session: session, connector: connector, probe: probe,
                            sessionID: sid, hostID: hostID)

        #expect(probe.events.contains { if case .established(let s) = $0 { return s == sid }; return false })
        #expect(probe.events.contains { if case .participantJoined(let p) = $0 { return p.id == hostID }; return false })
        #expect(probe.events.contains { if case .stateChanged(.active) = $0 { return true }; return false })
    }

    // MARK: 2. Таймаут подключения → .hostUnreachable

    @Test("connect timeout → ended(.hostUnreachable)")
    func connectTimeout() async throws {
        let (session, _, _) = makeSession(mode: .unreachable, configuration: .test)
        let probe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.hostUnreachable)) = $0 { return true }; return false
        }
    }

    // MARK: 3. localNetworkDenied → ended(.localNetworkDenied)

    @Test("localNetworkDenied → ended(.localNetworkDenied)")
    func localNetworkDenied() async throws {
        let (session, _, connector) = makeSession(mode: .unreachable)
        let probe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }

        // Ждём, пока сессия вызовет makeConnection и получит клиентский конец.
        let clientConn = try await waitForClient(connector: connector)
        clientConn.emit(.state(.waiting(.localNetworkDenied)))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.localNetworkDenied)) = $0 { return true }; return false
        }
    }

    // MARK: 4. Таймаут хэндшейка → .handshakeTimeout

    @Test("handshake timeout → ended(.handshakeTimeout)")
    func handshakeTimeout() async throws {
        let (session, _, connector) = makeSession(configuration: .test)
        let probe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }

        // Соединение создано и .ready эмитировано, но hostWelcome не отправляем.
        _ = try await waitForServer(connector: connector)

        // handshakeTimeout = 300 мс в .test конфигурации.
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.handshakeTimeout)) = $0 { return true }; return false
        }
    }

    // MARK: 5. Соединение закрыто до welcome → .rejected

    @Test("connection closed before hostWelcome → ended(.rejected)")
    func connectionClosedBeforeWelcome() async throws {
        let (session, _, connector) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }

        let serverConn = try await waitForServer(connector: connector)
        // emitFailure → клиент получает .cancelled → connectionClosed → .rejected
        serverConn.emitFailure()

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.rejected)) = $0 { return true }; return false
        }
    }

    // MARK: 6. hostWelcome status != "success" → .rejected

    @Test("hostWelcome status != success → ended(.rejected)")
    func welcomeStatusNotSuccess() async throws {
        let (session, _, connector) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }

        let serverConn = try await waitForServer(connector: connector)
        let badWelcome = HostWelcome(status: "full", sessionID: UUID(),
                                     hostPermanentPeerID: UUID(), hostNickname: "Host",
                                     participants: [])
        try await serverConn.send(.hostWelcome(badWelcome))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.rejected)) = $0 { return true }; return false
        }
    }

    // MARK: 7. Участники из hostWelcome → participantJoined для каждого

    @Test("participants in hostWelcome → participantJoined for each + host")
    func participantsFromWelcome() async throws {
        let (session, _, connector) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }

        let serverConn = try await waitForServer(connector: connector)
        let hostID = UUID()
        let peerA = PeerPayload(permanentPeerID: UUID(), nickname: "Alice")
        let peerB = PeerPayload(permanentPeerID: UUID(), nickname: "Bob")
        let welcome = HostWelcome(status: "success", sessionID: UUID(),
                                  hostPermanentPeerID: hostID, hostNickname: "Host",
                                  participants: [peerA, peerB])
        try await serverConn.send(.hostWelcome(welcome))

        // Ожидаем: host + Alice + Bob = 3 события participantJoined.
        let joined = try await probe.waitFor(count: 3, timeout: .seconds(5)) {
            if case .participantJoined = $0 { return true }; return false
        }
        let ids = joined.compactMap { e -> UUID? in
            if case .participantJoined(let p) = e { return p.id }; return nil
        }
        #expect(ids.contains(hostID))
        #expect(ids.contains(peerA.permanentPeerID))
        #expect(ids.contains(peerB.permanentPeerID))
    }

    // MARK: 8. chatMessage от хоста → messageReceived

    @Test("chatMessage from host → messageReceived event")
    func chatMessageFromHost() async throws {
        let (session, _, connector) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        let serverConn = try await handshake(session: session, connector: connector, probe: probe)

        let msgID = UUID()
        let payload = MessagePayload(messageID: msgID, senderID: UUID(),
                                     text: "Привет!", timestamp: Date())
        try await serverConn.send(.chatMessage(payload))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .messageReceived(let m) = $0 { return m.id == msgID }; return false
        }
    }

    // MARK: 9. sessionEnded от хоста → ended(.hostEnded)

    @Test("sessionEnded from host → ended(.hostEnded)")
    func sessionEndedFromHost() async throws {
        let (session, _, connector) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        let serverConn = try await handshake(session: session, connector: connector, probe: probe)

        try await serverConn.send(.sessionEnded(SessionEndedPayload(reason: "hostClosed")))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.hostEnded)) = $0 { return true }; return false
        }
    }

    // MARK: 10. Разрыв соединения после active → ended(.hostLost)

    @Test("connection dropped after active → ended(.hostLost)")
    func hostLostAfterActive() async throws {
        // Short grace (1,5 с) + unreachable reconnect → ended(.hostLost) быстро (§9.2).
        let (session, _, connector) = makeSession(configuration: .reliabilityShortGrace)
        let probe = EventProbe<SessionEvent>(stream: session.events)
        let serverConn = try await handshake(session: session, connector: connector, probe: probe)

        // Переключаем на unreachable до разрыва, чтобы попытки переподключения истекали.
        connector.setMode(.unreachable)
        serverConn.emitFailure()

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.hostLost)) = $0 { return true }; return false
        }
    }

    // MARK: 11. send(text:) → пакет доставлен хосту

    @Test("send(text:) → chatMessage packet delivered to host")
    func sendTextDelivered() async throws {
        let (session, _, connector) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        try await handshake(session: session, connector: connector, probe: probe)

        let sent = try await session.send(text: "hello")
        #expect(sent.text == "hello")

        // FakePeerConnection.send добавляет пакет в sentPackets синхронно до возврата,
        // поэтому пакет гарантированно доступен сразу после await session.send.
        let clientConn = connector.clientConnections.first!
        let hasChatMsg = clientConn.sentPackets.contains {
            if case .chatMessage(let m) = $0 { return m.messageID == sent.id }; return false
        }
        #expect(hasChatMsg, "chatMessage должен быть в sentPackets клиентского конца")
    }

    // MARK: 12. end() отправляет leave и переходит в ended(.leftByUser)

    // MARK: 13. leave() после ended(.hostLost) завершается немедленно

    @Test("leave() after ended(.hostLost) completes without hanging and sends no new packets")
    func leaveAfterHostLost() async throws {
        let (session, _, connector) = makeSession(configuration: .reliabilityShortGrace)
        let probe = EventProbe<SessionEvent>(stream: session.events)
        let serverConn = try await handshake(session: session, connector: connector, probe: probe)

        // Доводим сессию до ended(.hostLost)
        connector.setMode(.unreachable)
        serverConn.emitFailure()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.hostLost)) = $0 { return true }; return false
        }

        // Фиксируем число отправленных пакетов до вызова leave()
        let sentBefore = connector.clientConnections.map(\.sentPackets.count).reduce(0, +)

        // Вызываем leave() в отдельной задаче и ждём завершения (не должна зависнуть)
        let lock = NSLock()
        nonisolated(unsafe) var leaveFinished = false
        Task { await session.end(); lock.withLock { leaveFinished = true } }
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if lock.withLock({ leaveFinished }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(lock.withLock { leaveFinished }, "leave() не завершилась за 5 секунд")

        // После ended новых пакетов не отправлено
        let sentAfter = connector.clientConnections.map(\.sentPackets.count).reduce(0, +)
        #expect(sentBefore == sentAfter, "leave() не должна отправлять пакеты из ended-состояния")

        // В потоке событий ровно одно stateChanged(.ended)
        try await Task.sleep(for: .milliseconds(100))
        let endedCount = probe.events.filter {
            if case .stateChanged(.ended) = $0 { return true }; return false
        }.count
        #expect(endedCount == 1, "должно быть ровно одно stateChanged(.ended)")
    }

    @Test("end() → sends .leave and transitions to ended(.leftByUser)")
    func endSendsLeave() async throws {
        let (session, _, connector) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        try await handshake(session: session, connector: connector, probe: probe)

        await session.end()

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.leftByUser)) = $0 { return true }; return false
        }

        let clientConn = connector.clientConnections.first!
        let hasLeave = clientConn.sentPackets.contains { if case .leave = $0 { return true }; return false }
        #expect(hasLeave, "клиент должен отправить .leave перед завершением")
    }
}

// MARK: - Вспомогательные функции

/// Ждёт, пока `FakeClientConnector` создаст соединение, и возвращает серверный конец пары.
///
/// Серверный конец — это тот, кто получает пакеты от клиентской сессии и может отправлять
/// ей `hostWelcome`, `chatMessage` и т. д.
@MainActor
private func waitForServer(
    connector: FakeClientConnector,
    timeout: Duration = .seconds(5)
) async throws -> FakePeerConnection {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let server = connector.serverConnections.first { return server }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw EventProbeError.timeout(received: ["waitForServer: no server connection created"])
}

/// Ждёт, пока `FakeClientConnector` создаст соединение, и возвращает клиентский конец пары.
///
/// Используется в тестах, где нужно вручную управлять состоянием клиентского конца
/// (например, эмитировать `.waiting(.localNetworkDenied)`).
@MainActor
private func waitForClient(
    connector: FakeClientConnector,
    timeout: Duration = .seconds(5)
) async throws -> FakePeerConnection {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let client = connector.clientConnections.first { return client }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw EventProbeError.timeout(received: ["waitForClient: no client connection created"])
}

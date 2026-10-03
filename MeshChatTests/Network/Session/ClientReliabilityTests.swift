// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

/// Тесты надёжности `ClientSession`: heartbeat, тишина, переподключение, resume (§9.2, §9.6).
@MainActor
@Suite("ClientReliabilityTests", .serialized, .timeLimit(.minutes(2)))
struct ClientReliabilityTests {

    // MARK: - Вспомогательные методы

    func makeSecret() -> any RoomSecret {
        try! RoomCredentials(roomKeyData: Data(repeating: 0xEF, count: 32))
    }

    func makeSession(
        identity: LocalIdentity = .makeTest(),
        mode: ConnectionMode = .reachable,
        configuration: NetworkConfiguration = .reliability
    ) -> (ClientSession, FakeHostListener, FakeClientConnector) {
        let secret = makeSecret()
        let invite = RoomInvite(version: RoomInvite.currentVersion,
                                serviceName: UUID().uuidString,
                                roomKey: secret.roomKeyData)
        let listener = FakeHostListener()
        let connector = FakeClientConnector(listener: listener, mode: mode)
        let session = ClientSession(identity: identity, invite: invite, secret: secret,
                                    connector: connector, configuration: configuration)
        return (session, listener, connector)
    }

    /// Выполняет хэндшейк до `.active` и возвращает серверный конец соединения.
    @discardableResult
    func handshake(
        session: ClientSession,
        connector: FakeClientConnector,
        probe: EventProbe<SessionEvent>,
        sessionID: UUID = UUID(),
        hostID: UUID = UUID(),
        participants: [PeerPayload] = []
    ) async throws -> (serverConn: FakePeerConnection, sessionID: UUID) {
        Task { await session.start() }
        let serverConn = try await waitForServer(at: 1, in: connector)
        let welcome = HostWelcome(status: "success", sessionID: sessionID,
                                  hostPermanentPeerID: hostID, hostNickname: "Host",
                                  participants: participants)
        try await serverConn.send(.hostWelcome(welcome))
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }
        return (serverConn, sessionID)
    }

    // MARK: 1. Клиент отправляет ping хосту

    @Test("client sends ping to host")
    func clientSendsPing() async throws {
        let (session, _, connector) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        let (serverConn, _) = try await handshake(session: session, connector: connector, probe: probe)

        // Ждём heartbeatInterval (100 мс) — хост должен получить ping.
        _ = try await EventProbe<ConnectionEvent>(stream: serverConn.events).waitFor(timeout: .seconds(5)) {
            if case .packet(.ping) = $0 { return true }; return false
        }
    }

    // MARK: 2. Тишина от хоста → разрыв + reconnecting

    @Test("host silence triggers reconnecting state")
    func hostSilenceTriggersReconnect() async throws {
        let (session, _, connector) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        try await handshake(session: session, connector: connector, probe: probe)

        // Клиент получает pong (или любой пакет) при каждом ping хоста.
        // Обрываем провод: клиент не получает ответов → silenceTimeout (400 мс) → разрыв.
        connector.serverConnections.first?.sever()

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.reconnecting) = $0 { return true }; return false
        }
    }

    // MARK: 3. viability(false) → reconnecting; viability(true) → active (grace отменяется)

    @Test("viability flip: false enters reconnecting, true restores active")
    func viabilityFlip() async throws {
        let (session, _, connector) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)
        let (serverConn, _) = try await handshake(session: session, connector: connector, probe: probe)

        // Мягкий разрыв.
        serverConn.emit(.viability(false))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.reconnecting) = $0 { return true }; return false
        }

        // Восстановление: grace не истёк (5 с >> test time).
        serverConn.emit(.viability(true))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Убеждаемся, что ended не пришёл.
        try await Task.sleep(for: .milliseconds(200))
        #expect(!probe.events.contains {
            if case .stateChanged(.ended) = $0 { return true }; return false
        })
    }

    // MARK: 4. Успешное переподключение с тем же sessionID → reconcile участников

    @Test("reconnect with same sessionID reconciles participants")
    func reconnectReconciles() async throws {
        let secret = makeSecret()
        let invite = RoomInvite(version: RoomInvite.currentVersion,
                                serviceName: UUID().uuidString,
                                roomKey: secret.roomKeyData)
        let identity = LocalIdentity.makeTest(nickname: "Client")
        let listener = FakeHostListener()
        let connector = FakeClientConnector(listener: listener, mode: .reachable)
        let session = ClientSession(identity: identity, invite: invite, secret: secret,
                                    connector: connector, configuration: .reliabilityShortGrace)
        let probe = EventProbe<SessionEvent>(stream: session.events)

        let sid = UUID()
        let hostID = UUID()
        let aliceID = UUID()
        let alicePayload = PeerPayload(permanentPeerID: aliceID, nickname: "Alice")

        // Первый хэндшейк: Alice присутствует.
        Task { await session.start() }
        let server1 = try await waitForServer(at: 1, in: connector)
        let welcome1 = HostWelcome(status: "success", sessionID: sid,
                                   hostPermanentPeerID: hostID, hostNickname: "Host",
                                   participants: [alicePayload])
        try await server1.send(.hostWelcome(welcome1))
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Жёсткий разрыв → reconnecting.
        server1.emitFailure()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.reconnecting) = $0 { return true }; return false
        }

        // Второй хэндшейк: Alice ушла, Bob вошёл.
        let bobID = UUID()
        let bobPayload = PeerPayload(permanentPeerID: bobID, nickname: "Bob")
        let server2 = try await waitForServer(at: 2, in: connector, timeout: .seconds(3))
        let welcome2 = HostWelcome(status: "success", sessionID: sid,
                                   hostPermanentPeerID: hostID, hostNickname: "Host",
                                   participants: [bobPayload])
        try await server2.send(.hostWelcome(welcome2))
        // Ждём второго .active (probe помнит все события — ищем count: 2).
        _ = try await probe.waitFor(count: 2, timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Alice ушла → participantLeft(.connectionLost); Bob вошёл → participantJoined.
        let aliceLeft = probe.events.contains {
            if case .participantLeft(let p, .connectionLost) = $0 { return p.id == aliceID }
            return false
        }
        let bobJoined = probe.events.contains {
            if case .participantJoined(let p) = $0 { return p.id == bobID }; return false
        }
        #expect(aliceLeft, "Alice должна покинуть комнату с причиной .connectionLost")
        #expect(bobJoined, "Bob должен войти в комнату при reconcile")
    }

    // MARK: 5. Переподключение с другим sessionID → ended(.hostLost)

    @Test("reconnect with different sessionID → ended(.hostLost)")
    func reconnectDifferentSession() async throws {
        let (session, _, connector) = makeSession(configuration: .reliabilityShortGrace)
        let probe = EventProbe<SessionEvent>(stream: session.events)
        let (server1, _) = try await handshake(session: session, connector: connector, probe: probe)

        // Жёсткий разрыв → reconnecting.
        server1.emitFailure()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.reconnecting) = $0 { return true }; return false
        }

        // Хост перезапустил сессию — другой sessionID.
        let server2 = try await waitForServer(at: 2, in: connector, timeout: .seconds(3))
        let newSID = UUID()
        let welcome2 = HostWelcome(status: "success", sessionID: newSID,
                                   hostPermanentPeerID: UUID(), hostNickname: "Host",
                                   participants: [])
        try await server2.send(.hostWelcome(welcome2))

        _ = try await probe.waitFor(timeout: .seconds(3)) {
            if case .stateChanged(.ended(.hostLost)) = $0 { return true }; return false
        }
    }

    // MARK: 6. Grace period истёк → ended(.hostLost)

    @Test("grace period expiry → ended(.hostLost)")
    func gracePeriodExpiry() async throws {
        // unreachable: переподключения сразу падают, grace = 1,5 с.
        let (session, _, connector) = makeSession(mode: .reachable,
                                                  configuration: .reliabilityShortGrace)
        let probe = EventProbe<SessionEvent>(stream: session.events)
        let (serverConn, _) = try await handshake(session: session, connector: connector, probe: probe)

        connector.setMode(.unreachable)
        serverConn.emitFailure()

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.hostLost)) = $0 { return true }; return false
        }
    }

    // MARK: 7. end() во время reconnecting → ended(.leftByUser), без дополнительных событий

    @Test("end() during reconnecting → ended(.leftByUser)")
    func endDuringReconnecting() async throws {
        let (session, _, connector) = makeSession(configuration: .reliabilityShortGrace)
        let probe = EventProbe<SessionEvent>(stream: session.events)
        let (serverConn, _) = try await handshake(session: session, connector: connector, probe: probe)

        connector.setMode(.unreachable)
        serverConn.emitFailure()

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.reconnecting) = $0 { return true }; return false
        }

        await session.end()

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.leftByUser)) = $0 { return true }; return false
        }

        // Никаких ended(.hostLost) после leftByUser.
        try await Task.sleep(for: .milliseconds(100))
        let hostLostAfter = probe.events.drop(while: {
            if case .stateChanged(.ended(.leftByUser)) = $0 { return false }; return true
        }).contains {
            if case .stateChanged(.ended(.hostLost)) = $0 { return true }; return false
        }
        #expect(!hostLostAfter)
    }

    // MARK: 8. reconnectSessionID включается в clientHello при переподключении

    @Test("reconnect clientHello includes resumeSessionID")
    func reconnectHelloIncludesSessionID() async throws {
        let (session, _, connector) = makeSession(configuration: .reliabilityShortGrace)
        let probe = EventProbe<SessionEvent>(stream: session.events)
        let sid = UUID()
        let (server1, _) = try await handshake(session: session, connector: connector, probe: probe,
                                               sessionID: sid)

        server1.emitFailure()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.reconnecting) = $0 { return true }; return false
        }

        // Ждём второй clientHello.
        let client2 = try await waitForClient(at: 2, in: connector, timeout: .seconds(3))
        let sentPackets = client2.sentPackets
        let reconnectHello = sentPackets.compactMap { p -> ClientHello? in
            if case .clientHello(let h) = p { return h }; return nil
        }.first

        // reconnectHello может ещё не быть (ClientSession посылает его асинхронно).
        // Ждём, пока он появится в sentPackets.
        var hello: ClientHello?
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            let pkts = client2.sentPackets
            hello = pkts.compactMap { p -> ClientHello? in
                if case .clientHello(let h) = p { return h }; return nil
            }.first
            if hello != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        _ = reconnectHello  // suppress warning

        #expect(hello != nil, "clientHello должен быть отправлен при переподключении")
        #expect(hello?.resumeSessionID == sid,
                "resumeSessionID должен совпадать с sessionID первой сессии")
    }

    // MARK: 9. Несколько последовательных переподключений — каждое успешно

    @Test("multiple sequential reconnects succeed")
    func multipleReconnects() async throws {
        let secret = makeSecret()
        let invite = RoomInvite(version: RoomInvite.currentVersion,
                                serviceName: UUID().uuidString,
                                roomKey: secret.roomKeyData)
        let identity = LocalIdentity.makeTest(nickname: "MR")
        let listener = FakeHostListener()
        let connector = FakeClientConnector(listener: listener, mode: .reachable)
        let session = ClientSession(identity: identity, invite: invite, secret: secret,
                                    connector: connector, configuration: .reliabilityShortGrace)
        let probe = EventProbe<SessionEvent>(stream: session.events)

        let sid = UUID()
        let hostID = UUID()

        // Первый хэндшейк.
        Task { await session.start() }
        let s1 = try await waitForServer(at: 1, in: connector)
        try await s1.send(.hostWelcome(
            HostWelcome(status: "success", sessionID: sid,
                        hostPermanentPeerID: hostID, hostNickname: "H", participants: [])))
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Первый разрыв → reconnecting → второй хэндшейк.
        s1.emitFailure()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.reconnecting) = $0 { return true }; return false
        }
        let s2 = try await waitForServer(at: 2, in: connector, timeout: .seconds(3))
        try await s2.send(.hostWelcome(
            HostWelcome(status: "success", sessionID: sid,
                        hostPermanentPeerID: hostID, hostNickname: "H", participants: [])))
        // Ждём второго .active.
        _ = try await probe.waitFor(count: 2, timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Второй разрыв → reconnecting → третий хэндшейк.
        s2.emitFailure()
        _ = try await probe.waitFor(count: 2, timeout: .seconds(5)) {
            if case .stateChanged(.reconnecting) = $0 { return true }; return false
        }
        let s3 = try await waitForServer(at: 3, in: connector, timeout: .seconds(3))
        try await s3.send(.hostWelcome(
            HostWelcome(status: "success", sessionID: sid,
                        hostPermanentPeerID: hostID, hostNickname: "H", participants: [])))
        // Ждём третьего .active.
        _ = try await probe.waitFor(count: 3, timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Убеждаемся, что сессия не завершилась.
        #expect(!probe.events.contains {
            if case .stateChanged(.ended) = $0 { return true }; return false
        })
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

/// Тесты надёжности `HostSession`: heartbeat, тишина, suspended, resume, grace (§9.3, §9.6).
@MainActor
@Suite("HostReliabilityTests", .serialized, .timeLimit(.minutes(2)))
struct HostReliabilityTests {

    // MARK: - Вспомогательные методы

    func makeSecret() -> any RoomSecret {
        try! RoomCredentials(roomKeyData: Data(repeating: 0xAB, count: 32))
    }

    func makeSession(
        identity: LocalIdentity = .makeTest(),
        secret: any RoomSecret,
        configuration: NetworkConfiguration = .reliability
    ) -> (HostSession, FakeHostListener) {
        let l = FakeHostListener()
        return (HostSession(identity: identity, secret: secret, listener: l, configuration: configuration), l)
    }

    /// Запускает сессию и ждёт перехода в `.active`.
    func startActiveSession(
        identity: LocalIdentity = .makeTest(),
        secret: any RoomSecret,
        configuration: NetworkConfiguration = .reliability
    ) async throws -> (session: HostSession, listener: FakeHostListener, probe: EventProbe<SessionEvent>) {
        let (session, listener) = makeSession(identity: identity, secret: secret, configuration: configuration)
        let probe = EventProbe<SessionEvent>(stream: session.events)
        Task { await session.start() }
        listener.emitReady()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }
        return (session, listener, probe)
    }

    /// Подключает участника и ждёт `participantJoined` на `sessionProbe`.
    func addParticipant(
        identity: LocalIdentity,
        secret: any RoomSecret,
        listener: FakeHostListener,
        sessionProbe: EventProbe<SessionEvent>
    ) async throws -> (clientConn: FakePeerConnection, welcome: HostWelcome, clientProbe: EventProbe<ConnectionEvent>) {
        let (clientConn, serverConn) = FakePeerConnection.makePair()
        listener.accept(serverConn)
        let (welcome, clientProbe) = try await playClient(
            connection: clientConn, identity: identity, secret: secret, timeout: .seconds(3)
        )
        _ = try await sessionProbe.waitFor(timeout: .seconds(5)) {
            if case .participantJoined(let p) = $0 { return p.id == identity.peerID }; return false
        }
        return (clientConn, welcome, clientProbe)
    }

    // MARK: 1. Хост отвечает pong на ping клиента

    @Test("host responds pong to client ping")
    func hostSendsPong() async throws {
        let secret = makeSecret()
        let (_, listener, sessionProbe) = try await startActiveSession(secret: secret)
        let clientIdentity = LocalIdentity.makeTest(nickname: "Alice")
        let (clientConn, _, clientProbe) = try await addParticipant(
            identity: clientIdentity, secret: secret, listener: listener, sessionProbe: sessionProbe
        )

        let sentAt = Date()
        try await clientConn.send(.ping(HeartbeatPayload(sentAt: sentAt)))

        _ = try await clientProbe.waitFor(timeout: .seconds(5)) {
            if case .packet(.pong(let p)) = $0 { return p.sentAt == sentAt }; return false
        }
    }

    // MARK: 2. Тишина → suspended без participantLeft

    @Test("silence timeout suspends participant without emitting participantLeft")
    func silenceDetectedNoLeaveYet() async throws {
        let secret = makeSecret()
        // grace = 5 с — participantLeft не придёт в течение теста
        let (_, listener, sessionProbe) = try await startActiveSession(
            secret: secret, configuration: .reliability
        )
        let clientIdentity = LocalIdentity.makeTest(nickname: "Bob")
        let (clientConn, _, _) = try await addParticipant(
            identity: clientIdentity, secret: secret, listener: listener, sessionProbe: sessionProbe
        )

        // Обрываем провод: пакеты не доставляются → монитор тишины сработает через silenceTimeout (400 мс)
        clientConn.sever()

        // Ждём достаточно для детектирования тишины: silenceTimeout + heartbeatInterval = 500 мс
        try await Task.sleep(for: .milliseconds(600))

        // Grace period (5 с) не истёк → participantLeft не должен прийти
        #expect(!sessionProbe.events.contains {
            if case .participantLeft(let p, _) = $0 { return p.id == clientIdentity.peerID }
            return false
        })
    }

    // MARK: 3. Suspended-участник не получает ретранслированные сообщения

    @Test("suspended participant does not receive relayed message")
    func suspendedParticipantNotRelayed() async throws {
        let secret = makeSecret()
        let (_, listener, sessionProbe) = try await startActiveSession(secret: secret)

        let idA = LocalIdentity.makeTest(nickname: "A")
        let idB = LocalIdentity.makeTest(nickname: "B")

        let (connA, _, probeA) = try await addParticipant(
            identity: idA, secret: secret, listener: listener, sessionProbe: sessionProbe
        )
        let (connB, _, _) = try await addParticipant(
            identity: idB, secret: secret, listener: listener, sessionProbe: sessionProbe
        )

        // A имитирует разрыв → runPacketLoop завершается → suspendParticipant (§9.3)
        // emitFailure используется вместо sever()+600мс: sever вызвал бы и силенс-таймер B (400мс).
        connA.emitFailure()
        try await Task.sleep(for: .milliseconds(50))

        // B отправляет сообщение → хост получает, но ретранслирует только активным (не A)
        let msgID = UUID()
        try await connB.send(.chatMessage(
            MessagePayload(messageID: msgID, senderID: idB.peerID, text: "hi", timestamp: Date())
        ))

        _ = try await sessionProbe.waitFor(timeout: .seconds(5)) {
            if case .messageReceived(let m) = $0 { return m.id == msgID }; return false
        }

        // A не должен получить пакет
        try await Task.sleep(for: .milliseconds(50))
        #expect(!probeA.events.contains {
            if case .packet(.chatMessage(let m)) = $0 { return m.messageID == msgID }
            return false
        })
    }

    // MARK: 4. Истечение grace period → participantLeft(.connectionLost)

    @Test("grace period expiry emits participantLeft(.connectionLost)")
    func graceExpiry() async throws {
        let secret = makeSecret()
        // Короткий grace = 1,5 с для ускорения теста
        let (_, listener, sessionProbe) = try await startActiveSession(
            secret: secret, configuration: .reliabilityShortGrace
        )
        let clientIdentity = LocalIdentity.makeTest(nickname: "Charlie")
        let (clientConn, _, _) = try await addParticipant(
            identity: clientIdentity, secret: secret, listener: listener, sessionProbe: sessionProbe
        )

        // emitFailure → runPacketLoop завершается → suspendParticipant → grace таймер стартует
        clientConn.emitFailure()

        _ = try await sessionProbe.waitFor(timeout: .seconds(5)) {
            if case .participantLeft(let p, let r) = $0 {
                return p.id == clientIdentity.peerID && r == .connectionLost
            }
            return false
        }
    }

    // MARK: 5. viability(false) → suspended; viability(true) → active (grace отменяется)

    @Test("viability flip: false suspends, true resumes and cancels grace")
    func viabilityFlip() async throws {
        let secret = makeSecret()
        let (_, listener, sessionProbe) = try await startActiveSession(secret: secret)
        let clientIdentity = LocalIdentity.makeTest(nickname: "Dana")
        let (clientConn, _, _) = try await addParticipant(
            identity: clientIdentity, secret: secret, listener: listener, sessionProbe: sessionProbe
        )

        // Мягкая потеря → suspended, grace стартует
        clientConn.emit(.viability(false))
        try await Task.sleep(for: .milliseconds(50))

        // Восстановление → grace отменяется, isSuspended = false
        clientConn.emit(.viability(true))

        // Ждём больше heartbeatInterval, но значительно меньше gracePeriod (5 с)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!sessionProbe.events.contains {
            if case .participantLeft(let p, _) = $0 { return p.id == clientIdentity.peerID }
            return false
        })
    }

    // MARK: 6. Резюм через новый clientHello от suspended участника — без join/leave

    @Test("resume via new clientHello: no participantJoined or participantLeft events")
    func resumeViaClientHello() async throws {
        let secret = makeSecret()
        let (session, listener, sessionProbe) = try await startActiveSession(secret: secret)
        let clientIdentity = LocalIdentity.makeTest(nickname: "Eve")
        let (clientConn, _, _) = try await addParticipant(
            identity: clientIdentity, secret: secret, listener: listener, sessionProbe: sessionProbe
        )

        // Тишина → suspended (grace 5 с не истечёт за время теста)
        clientConn.sever()
        try await Task.sleep(for: .milliseconds(600))

        // Новое соединение с тем же peerID → резюм
        let (newClient, newServer) = FakePeerConnection.makePair()
        listener.accept(newServer)
        let (welcome, _) = try await playClient(
            connection: newClient, identity: clientIdentity, secret: secret, timeout: .seconds(3)
        )
        #expect(welcome.sessionID == session.sessionID)

        // Ждём распространения событий
        try await Task.sleep(for: .milliseconds(100))

        // Ровно одно participantJoined (при первоначальном входе) — нового не должно быть
        let joinEvents = sessionProbe.events.filter {
            if case .participantJoined(let p) = $0 { return p.id == clientIdentity.peerID }; return false
        }
        #expect(joinEvents.count == 1)

        // Никаких participantLeft
        #expect(!sessionProbe.events.contains {
            if case .participantLeft(let p, _) = $0 { return p.id == clientIdentity.peerID }; return false
        })
    }

    // MARK: 7. Suspended-участник занимает слот в maxClients

    @Test("suspended participant occupies maxClients slot — 5th client rejected")
    func suspendedOccupiesSlot() async throws {
        let secret = makeSecret()
        let (_, listener, sessionProbe) = try await startActiveSession(secret: secret)

        // Заполняем 4 слота
        var conns: [FakePeerConnection] = []
        for i in 0..<4 {
            let id = LocalIdentity.makeTest(nickname: "P\(i)")
            let (conn, _, _) = try await addParticipant(
                identity: id, secret: secret, listener: listener, sessionProbe: sessionProbe
            )
            conns.append(conn)
        }

        // Подвешиваем первый слот через viability(false)
        conns[0].emit(.viability(false))
        try await Task.sleep(for: .milliseconds(50))

        // 5-й клиент пытается войти — комната всё ещё полная (suspended считается)
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

        let fifthProbe = EventProbe<ConnectionEvent>(stream: fifthClient.events)
        _ = try await fifthProbe.waitFor(timeout: .seconds(5)) {
            if case .state(.cancelled) = $0 { return true }; return false
        }
        _ = conns
    }

    // MARK: 8. Добровольный leave — немедленный, без grace

    @Test("voluntary leave emits participantLeft(.left) immediately without grace")
    func voluntaryLeaveImmediate() async throws {
        let secret = makeSecret()
        let (_, listener, sessionProbe) = try await startActiveSession(secret: secret)
        let clientIdentity = LocalIdentity.makeTest(nickname: "Frank")
        let (clientConn, _, _) = try await addParticipant(
            identity: clientIdentity, secret: secret, listener: listener, sessionProbe: sessionProbe
        )

        try await clientConn.send(.leave)

        _ = try await sessionProbe.waitFor(timeout: .seconds(5)) {
            if case .participantLeft(let p, .left) = $0 { return p.id == clientIdentity.peerID }
            return false
        }
    }
}

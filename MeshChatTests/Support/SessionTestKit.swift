// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

// MARK: - Тестовая конфигурация

extension NetworkConfiguration {
    /// Сверхкороткие таймауты для юнит-тестов сессий.
    static let test = NetworkConfiguration(
        serviceType: "_meshchat._tcp",
        maxClients: 4,
        connectTimeout: .milliseconds(200),
        handshakeTimeout: .milliseconds(300),
        heartbeatInterval: .seconds(60),
        silenceTimeout: .seconds(60),
        reconnectGracePeriod: .seconds(60),
        reconnectBackoff: [.milliseconds(50)],
        sessionEndFlushTimeout: .milliseconds(100)
    )
}

// MARK: - Фабрика идентичностей

extension LocalIdentity {
    /// Создаёт тестовую идентичность с уникальным `peerID`.
    static func makeTest(nickname: String = "Tester") -> LocalIdentity {
        LocalIdentity(peerID: UUID(), nickname: nickname)
    }
}

// MARK: - "Сыграть клиента"

/// Отправляет `clientHello` от имени `identity` и ждёт `hostWelcome`.
///
/// Используется в тестах `HostSession`: клиентский конец пары передаётся сюда,
/// пока `HostSession` держит серверный конец.
///
/// - Throws: `EventProbeError.timeout` если `hostWelcome` не пришёл за 2 с.
@discardableResult
func playClient(
    connection: FakePeerConnection,
    identity: LocalIdentity,
    secret: any RoomSecret,
    timeout: Duration = .seconds(2)
) async throws -> HostWelcome {
    let probe = EventProbe<ConnectionEvent>(stream: connection.events)
    let hello = ClientHello(
        protocolVersion: PacketCodec.protocolVersion,
        authToken: secret.authToken(for: identity.peerID),
        permanentPeerID: identity.peerID,
        nickname: identity.nickname,
        resumeSessionID: nil
    )
    try await connection.send(.clientHello(hello))
    let event = try await probe.waitFor(timeout: timeout) {
        if case .packet(.hostWelcome) = $0 { return true }; return false
    }
    guard case .packet(.hostWelcome(let welcome)) = event else {
        throw EventProbeError.timeout(received: [])
    }
    return welcome
}

// MARK: - Быстрый самотест

@Suite("SessionTestKit self-test")
struct SessionTestKitSelfTests {

    @Test("FakePeerConnection pair: send arrives as .packet on peer")
    func fakePairDelivery() async throws {
        let (a, b) = FakePeerConnection.makePair()
        a.start(); b.start()
        let probeB = EventProbe<ConnectionEvent>(stream: b.events)
        let msg = MessagePayload(messageID: UUID(), senderID: UUID(),
                                 text: "ping", timestamp: Date())
        try await a.send(.chatMessage(msg))
        _ = try await probeB.waitFor(timeout: .seconds(1)) {
            if case .packet(.chatMessage(let m)) = $0 { return m.messageID == msg.messageID }
            return false
        }
    }

    @Test("FakePeerConnection cancel: both ends get .cancelled and streams finish")
    func fakePairCancel() async throws {
        let (a, b) = FakePeerConnection.makePair()
        a.start(); b.start()
        let probeA = EventProbe<ConnectionEvent>(stream: a.events)
        let probeB = EventProbe<ConnectionEvent>(stream: b.events)
        a.cancel()
        try await probeA.waitForFinish(timeout: .seconds(1))
        try await probeB.waitForFinish(timeout: .seconds(1))
        #expect(probeA.events.contains { if case .state(.cancelled) = $0 { return true }; return false })
        #expect(probeB.events.contains { if case .state(.cancelled) = $0 { return true }; return false })
    }

    @Test("FakeHostListener: emitReady and accept deliver events")
    func fakeListenerEvents() async throws {
        let listener = FakeHostListener()
        let stream = try listener.start(serviceName: "test", security: .plaintext)
        let probe = EventProbe<ListenerEvent>(stream: stream)
        listener.emitReady(port: 8080)
        let (clientConn, _) = FakePeerConnection.makePair()
        listener.accept(clientConn)
        let ready = try await probe.waitFor(timeout: .seconds(1)) {
            if case .ready = $0 { return true }; return false
        }
        guard case .ready(let port) = ready else { Issue.record("no ready"); return }
        #expect(port == 8080)
        _ = try await probe.waitFor(timeout: .seconds(1)) {
            if case .incoming = $0 { return true }; return false
        }
    }

    @Test("FakeClientConnector: makeConnection links client to listener")
    func fakeConnectorLinksToListener() async throws {
        let listener = FakeHostListener()
        let stream = try listener.start(serviceName: "test", security: .plaintext)
        let listenerProbe = EventProbe<ListenerEvent>(stream: stream)
        listener.emitReady(port: 0)

        let connector = FakeClientConnector(listener: listener)
        let client = connector.makeConnection(serviceName: "test", security: .plaintext)
        #expect(connector.clientConnections.count == 1)

        _ = try await listenerProbe.waitFor(timeout: .seconds(1)) {
            if case .incoming = $0 { return true }; return false
        }
        _ = client  // keep alive
    }
}

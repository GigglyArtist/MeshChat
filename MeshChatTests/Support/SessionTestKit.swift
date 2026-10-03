// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

// MARK: - Тестовые конфигурации

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

    /// Таймауты для интеграционных тестов сессий через loopback (реальный TLS требует больше времени).
    static let loopback = NetworkConfiguration(
        serviceType: "_meshchat._tcp",
        maxClients: 4,
        connectTimeout: .seconds(5),
        handshakeTimeout: .seconds(5),
        heartbeatInterval: .seconds(60),
        silenceTimeout: .seconds(60),
        reconnectGracePeriod: .seconds(60),
        reconnectBackoff: [.milliseconds(200)],
        sessionEndFlushTimeout: .milliseconds(500)
    )

    /// Конфигурация для тестов надёжности: heartbeat и тишина (§9.6).
    ///
    /// `heartbeatInterval` 100 мс, `silenceTimeout` 400 мс, `reconnectGracePeriod` 5 с.
    static let reliability = NetworkConfiguration(
        serviceType: "_meshchat._tcp",
        maxClients: 4,
        connectTimeout: .seconds(2),
        handshakeTimeout: .seconds(2),
        heartbeatInterval: .milliseconds(100),
        silenceTimeout: .milliseconds(400),
        reconnectGracePeriod: .seconds(5),
        reconnectBackoff: [.milliseconds(50), .milliseconds(100), .milliseconds(200)],
        sessionEndFlushTimeout: .milliseconds(100)
    )

    /// Конфигурация для тестов перезапуска listener'а (ADR-11).
    ///
    /// Короткий `reconnectBackoff` [50, 100 мс] для быстрого перезапуска.
    static let listenerRestart = NetworkConfiguration(
        serviceType: "_meshchat._tcp",
        maxClients: 4,
        connectTimeout: .seconds(2),
        handshakeTimeout: .seconds(2),
        heartbeatInterval: .seconds(60),
        silenceTimeout: .seconds(60),
        reconnectGracePeriod: .seconds(60),
        reconnectBackoff: [.milliseconds(50), .milliseconds(100)],
        sessionEndFlushTimeout: .milliseconds(100)
    )

    /// Конфигурация для тестов истечения грейс-периода (§9.6).
    ///
    /// Идентична `.reliability`, но `reconnectGracePeriod` сокращён до 1,5 с.
    static let reliabilityShortGrace = NetworkConfiguration(
        serviceType: "_meshchat._tcp",
        maxClients: 4,
        connectTimeout: .seconds(2),
        handshakeTimeout: .seconds(2),
        heartbeatInterval: .milliseconds(100),
        silenceTimeout: .milliseconds(400),
        reconnectGracePeriod: .milliseconds(1500),
        reconnectBackoff: [.milliseconds(50), .milliseconds(100), .milliseconds(200)],
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
/// пока `HostSession` держит серверный конец. Возвращает зонд, чтобы тест мог
/// продолжать читать события с этого соединения после хэндшейка.
///
/// - Throws: `EventProbeError.timeout` если `hostWelcome` не пришёл за `timeout`.
@discardableResult
func playClient(
    connection: FakePeerConnection,
    identity: LocalIdentity,
    secret: any RoomSecret,
    timeout: Duration = .seconds(5)
) async throws -> (welcome: HostWelcome, probe: EventProbe<ConnectionEvent>) {
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
    return (welcome, probe)
}

/// Отправляет `clientHello` с `resumeSessionID` и ждёт `hostWelcome` (§9.6).
@discardableResult
func playClientWithResume(
    connection: FakePeerConnection,
    identity: LocalIdentity,
    secret: any RoomSecret,
    resumeSessionID: UUID,
    timeout: Duration = .seconds(5)
) async throws -> (welcome: HostWelcome, probe: EventProbe<ConnectionEvent>) {
    let probe = EventProbe<ConnectionEvent>(stream: connection.events)
    let hello = ClientHello(
        protocolVersion: PacketCodec.protocolVersion,
        authToken: secret.authToken(for: identity.peerID),
        permanentPeerID: identity.peerID,
        nickname: identity.nickname,
        resumeSessionID: resumeSessionID
    )
    try await connection.send(.clientHello(hello))
    let event = try await probe.waitFor(timeout: timeout) {
        if case .packet(.hostWelcome) = $0 { return true }; return false
    }
    guard case .packet(.hostWelcome(let welcome)) = event else {
        throw EventProbeError.timeout(received: [])
    }
    return (welcome, probe)
}

// MARK: - Ожидание соединений в FakeClientConnector

/// Ждёт появления серверного конца с индексом `index` (с 1) в `connector`.
func waitForServer(
    at index: Int = 1,
    in connector: FakeClientConnector,
    timeout: Duration = .seconds(5)
) async throws -> FakePeerConnection {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        let servers = connector.serverConnections
        if servers.count >= index { return servers[index - 1] }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw EventProbeError.timeout(
        received: ["waitForServer(at:\(index)): only \(connector.serverConnections.count) connections"]
    )
}

/// Ждёт появления клиентского конца с индексом `index` (с 1) в `connector`.
func waitForClient(
    at index: Int = 1,
    in connector: FakeClientConnector,
    timeout: Duration = .seconds(5)
) async throws -> FakePeerConnection {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        let clients = connector.clientConnections
        if clients.count >= index { return clients[index - 1] }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw EventProbeError.timeout(
        received: ["waitForClient(at:\(index)): only \(connector.clientConnections.count) connections"]
    )
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

    @Test("FakePeerConnection sever: send succeeds but packet is not delivered")
    func fakePairSever() async throws {
        let (a, b) = FakePeerConnection.makePair()
        a.start(); b.start()
        let probeB = EventProbe<ConnectionEvent>(stream: b.events)

        a.sever()

        let msgID = UUID()
        let msg = MessagePayload(messageID: msgID, senderID: UUID(),
                                 text: "ghost", timestamp: Date())
        // send не бросает — соединение «живо»
        try await a.send(.chatMessage(msg))
        #expect(a.sentPackets.count == 1)
        // Даём EventProbe время на доставку (которой не должно быть)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!probeB.events.contains {
            if case .packet(.chatMessage(let m)) = $0 { return m.messageID == msgID }
            return false
        })
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

    @Test("FakeClientConnector unreachable: connection never becomes .ready")
    func fakeConnectorUnreachable() async throws {
        let listener = FakeHostListener()
        _ = try listener.start(serviceName: "test", security: .plaintext)

        let connector = FakeClientConnector(listener: listener, mode: .unreachable)
        let client = connector.makeConnection(serviceName: "test", security: .plaintext) as! FakePeerConnection
        let probe = EventProbe<ConnectionEvent>(stream: client.events)
        client.start()
        // .ready не должно прийти за 100 мс
        try await Task.sleep(for: .milliseconds(100))
        #expect(!probe.events.contains { if case .state(.ready) = $0 { return true }; return false })
    }

    @Test("FakeHostListener restart: start → emitFailure → start → emitReady gives two streams, startCount == 2")
    func fakeListenerRestart() async throws {
        let listener = FakeHostListener()

        // Первый запуск — эмитим failure
        let stream1 = try listener.start(serviceName: "room-A", security: .plaintext)
        let probe1 = EventProbe<ListenerEvent>(stream: stream1)
        listener.emitFailure(.other("link down"))
        try await probe1.waitForFinish(timeout: .seconds(1))
        #expect(probe1.events.contains { if case .failed = $0 { return true }; return false })

        // Второй запуск — эмитим ready
        let stream2 = try listener.start(serviceName: "room-A", security: .plaintext)
        let probe2 = EventProbe<ListenerEvent>(stream: stream2)
        listener.emitReady(port: 5555)
        let readyEvent = try await probe2.waitFor(timeout: .seconds(1)) {
            if case .ready = $0 { return true }; return false
        }
        guard case .ready(let port) = readyEvent else { Issue.record("expected .ready"); return }
        #expect(port == 5555)

        #expect(listener.startCount == 2)
        #expect(listener.stopCount == 0)
    }

    @Test("FakeHostListener setNextStartThrows: second start throws, third succeeds")
    func fakeListenerThrowsOnce() async throws {
        let listener = FakeHostListener()

        // Первый запуск нормальный
        let stream1 = try listener.start(serviceName: "room-B", security: .plaintext)
        listener.emitFailure()
        let probe1 = EventProbe<ListenerEvent>(stream: stream1)
        try await probe1.waitForFinish(timeout: .seconds(1))

        // Второй должен бросить
        listener.setNextStartThrows()
        #expect(throws: FakeListenerError.simulatedStartFailure) {
            try listener.start(serviceName: "room-B", security: .plaintext)
        }
        // startCount не увеличился
        #expect(listener.startCount == 1)

        // Третий нормальный
        let stream3 = try listener.start(serviceName: "room-B", security: .plaintext)
        #expect(listener.startCount == 2)
        let probe3 = EventProbe<ListenerEvent>(stream: stream3)
        listener.emitReady()
        _ = try await probe3.waitFor(timeout: .seconds(1)) { if case .ready = $0 { return true }; return false }
    }
}

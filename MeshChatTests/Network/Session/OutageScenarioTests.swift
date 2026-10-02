// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

/// Сквозные тесты сценариев отказа: HostSession + ClientSession через FakeNetwork (§9.2, §9.3, §9.6).
///
/// Каждый сценарий поднимает полноценную пару сессий через общий `FakeHostListener` /
/// `FakeClientConnector`, имитирует обрыв и проверяет поведение обеих сторон.
@MainActor
@Suite("OutageScenarioTests", .serialized, .timeLimit(.minutes(2)))
struct OutageScenarioTests {

    // MARK: - Вспомогательные методы

    func makeSecret() -> any RoomSecret {
        try! RoomCredentials(roomKeyData: Data(repeating: 0x77, count: 32))
    }

    /// Поднимает пару HostSession + ClientSession и ждёт, пока обе стороны перейдут в `.active`.
    ///
    /// - Returns: кортеж (host, client, хост-зонд, клиент-зонд, коннектор).
    func buildAndConnect(
        hostIdentity: LocalIdentity = .makeTest(nickname: "Host"),
        clientIdentity: LocalIdentity = .makeTest(nickname: "Client"),
        configuration: NetworkConfiguration = .reliability
    ) async throws -> (
        host: HostSession,
        client: ClientSession,
        hostProbe: EventProbe<SessionEvent>,
        clientProbe: EventProbe<SessionEvent>,
        connector: FakeClientConnector
    ) {
        let secret = makeSecret()
        let listener = FakeHostListener()
        let connector = FakeClientConnector(listener: listener, mode: .reachable)
        let invite = RoomInvite(version: RoomInvite.currentVersion,
                                serviceName: UUID().uuidString,
                                roomKey: secret.roomKeyData)

        let host = HostSession(identity: hostIdentity, secret: secret,
                               listener: listener, configuration: configuration)
        let client = ClientSession(identity: clientIdentity, invite: invite, secret: secret,
                                   connector: connector, configuration: configuration)

        let hostProbe = EventProbe<SessionEvent>(stream: host.events)
        let clientProbe = EventProbe<SessionEvent>(stream: client.events)

        Task { await host.start() }
        listener.emitReady()
        _ = try await hostProbe.waitFor(timeout: .seconds(3)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        Task { await client.start() }
        _ = try await hostProbe.waitFor(timeout: .seconds(3)) {
            if case .participantJoined(let p) = $0 { return p.id == clientIdentity.peerID }; return false
        }
        _ = try await clientProbe.waitFor(timeout: .seconds(3)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        return (host, client, hostProbe, clientProbe, connector)
    }

    /// Запускает тест с полноценной парой сессий и гарантирует их завершение после тела теста.
    ///
    /// `end()` вызывается на обеих сессиях вне зависимости от того, упал ли тест.
    /// Это прекращает внутренние задачи (heartbeat, silence, grace) до начала следующего теста,
    /// устраняя конкуренцию за кооперативный пул потоков.
    func withConnectedSessions(
        hostIdentity: LocalIdentity = .makeTest(nickname: "Host"),
        clientIdentity: LocalIdentity,
        configuration: NetworkConfiguration = .reliabilityShortGrace,
        body: @MainActor (
            HostSession, ClientSession,
            EventProbe<SessionEvent>, EventProbe<SessionEvent>,
            FakeClientConnector
        ) async throws -> Void
    ) async throws {
        let (host, client, hostProbe, clientProbe, connector) = try await buildAndConnect(
            hostIdentity: hostIdentity,
            clientIdentity: clientIdentity,
            configuration: configuration
        )
        var savedError: (any Error)?
        do {
            try await body(host, client, hostProbe, clientProbe, connector)
        } catch {
            savedError = error
        }
        // Останавливаем обе сессии: прерываем heartbeat/silence/grace tasks
        // и даём внешним Task { await *.start() } завершиться естественным путём.
        await host.end()
        await client.end()
        if let e = savedError { throw e }
    }

    // MARK: 1. Клиент переподключается к тому же хосту — без join/leave событий

    @Test("client reconnects to same host: no participantLeft or extra participantJoined")
    func clientReconnectsToSameHost() async throws {
        let clientIdentity = LocalIdentity.makeTest(nickname: "Alice")
        let clientPeerID = clientIdentity.peerID
        try await withConnectedSessions(clientIdentity: clientIdentity) { _, _, hostProbe, clientProbe, connector in
            // Разрываем соединение: клиентский конец имитирует отказ.
            connector.clientConnections[0].emitFailure()

            // Клиент переходит в reconnecting.
            _ = try await clientProbe.waitFor(timeout: .seconds(2)) {
                if case .stateChanged(.reconnecting) = $0 { return true }; return false
            }

            // Клиент успешно переподключается → второй .active.
            _ = try await clientProbe.waitFor(count: 2, timeout: .seconds(5)) {
                if case .stateChanged(.active) = $0 { return true }; return false
            }

            // Ждём распространения событий.
            try await Task.sleep(for: .milliseconds(100))

            // Хост не должен выдавать participantLeft для этого клиента (он был suspended, а не ушёл).
            let noLeftEvent = !hostProbe.events.contains { event in
                if case .participantLeft(let p, _) = event { return p.id == clientPeerID }
                return false
            }
            #expect(noLeftEvent, "host must not emit participantLeft for a reconnected client")

            // Клиент не должен получить повторный participantJoined для хоста
            // (established повторно не выдаётся при resume).
            let establishedCount = clientProbe.events.filter {
                if case .established = $0 { return true }; return false
            }.count
            #expect(establishedCount == 1, "established emitted more than once on resume")
        }
    }

    // MARK: 2. Grace period истёк: хост выдаёт participantLeft, клиент — ended(.hostLost)

    @Test("grace expiry: host emits participantLeft(.connectionLost), client emits ended(.hostLost)")
    func graceExpiryBothSides() async throws {
        let clientIdentity = LocalIdentity.makeTest(nickname: "Bob")
        let clientPeerID = clientIdentity.peerID
        try await withConnectedSessions(clientIdentity: clientIdentity) { _, _, hostProbe, clientProbe, connector in
            // Переключаем коннектор на unreachable — переподключения не состоятся.
            connector.setMode(.unreachable)
            connector.clientConnections[0].emitFailure()

            // Обе стороны должны зафиксировать потерю соединения.
            _ = try await hostProbe.waitFor(timeout: .seconds(5)) {
                if case .participantLeft(let p, .connectionLost) = $0 {
                    return p.id == clientPeerID
                }
                return false
            }

            _ = try await clientProbe.waitFor(timeout: .seconds(5)) {
                if case .stateChanged(.ended(.hostLost)) = $0 { return true }; return false
            }
        }
    }

    // MARK: 3. Обмен сообщениями до и после переподключения

    @Test("messages flow before and after client reconnect")
    func messagesBeforeAndAfterReconnect() async throws {
        let clientIdentity = LocalIdentity.makeTest(nickname: "Carol")
        try await withConnectedSessions(clientIdentity: clientIdentity) { host, client, hostProbe, clientProbe, connector in
            // Сообщение до обрыва.
            let msg1 = try await client.send(text: "before outage")
            _ = try await hostProbe.waitFor(timeout: .seconds(2)) {
                if case .messageReceived(let m) = $0 { return m.id == msg1.id }; return false
            }

            // Разрыв → переподключение.
            connector.clientConnections[0].emitFailure()
            _ = try await clientProbe.waitFor(count: 2, timeout: .seconds(5)) {
                if case .stateChanged(.active) = $0 { return true }; return false
            }

            // Сообщение после переподключения.
            let msg2 = try await client.send(text: "after reconnect")
            _ = try await hostProbe.waitFor(timeout: .seconds(2)) {
                if case .messageReceived(let m) = $0 { return m.id == msg2.id }; return false
            }

            // Убеждаемся, что оба сообщения зафиксированы хостом.
            let received = hostProbe.events.compactMap { e -> ChatMessage? in
                if case .messageReceived(let m) = e { return m }; return nil
            }
            #expect(received.map(\.id).contains(msg1.id), "first message must be received")
            #expect(received.map(\.id).contains(msg2.id), "second message must be received")

            _ = host  // keep alive
            _ = client
        }
    }
}

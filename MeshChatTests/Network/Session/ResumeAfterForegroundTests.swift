// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

/// `@MainActor` нужен потому, что с `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
/// инициализаторы акторов `HostSession` и `ClientSession` выводятся как `@MainActor`-изолированные.
@MainActor
@Suite("ResumeAfterForegroundTests", .serialized, .timeLimit(.minutes(1)))
struct ResumeAfterForegroundTests {

    // MARK: - Вспомогательный метод

    func makeSecret() -> any RoomSecret {
        try! RoomCredentials(roomKeyData: Data(repeating: 0xCD, count: 32))
    }

    /// Конфигурация с большим backoff: гарантирует, что без `resumeAfterForeground()`
    /// второй запуск listener'а / переподключение заняли бы 30 секунд.
    var longBackoffConfig: NetworkConfiguration {
        NetworkConfiguration(
            serviceType: "_meshchat._tcp",
            maxClients: 4,
            connectTimeout: .seconds(2),
            handshakeTimeout: .seconds(2),
            heartbeatInterval: .seconds(60),
            silenceTimeout: .seconds(60),
            reconnectGracePeriod: .seconds(60),
            reconnectBackoff: [.seconds(30)],
            sessionEndFlushTimeout: .milliseconds(100)
        )
    }

    // MARK: - Тест 1: хост — resumeAfterForeground пропускает паузу перезапуска

    @Test("Host: resumeAfterForeground skips restart backoff")
    func hostResumeSkipsBackoff() async throws {
        let listener = FakeHostListener()
        let session = HostSession(
            identity: .makeTest(nickname: "Host"),
            secret: makeSecret(),
            listener: listener,
            configuration: longBackoffConfig
        )
        let probe = EventProbe<SessionEvent>(stream: session.events)

        Task { await session.start() }
        listener.emitReady()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Listener падает → задача уходит в 30-секундный backoff
        listener.emitFailure(.other("link down"))

        // Немедленно вызываем resumeAfterForeground — должно пропустить паузу
        await session.resumeAfterForeground()

        // Второй запуск listener'а должен произойти быстро (без 30-секундного ожидания)
        let deadline = ContinuousClock.now + .seconds(5)
        while listener.startCount < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(listener.startCount == 2, "resumeAfterForeground should bypass backoff")

        await session.end()
    }

    // MARK: - Тест 2: хост — resumeAfterForeground no-op когда нет активного перезапуска

    @Test("Host: resumeAfterForeground is no-op when listener is running")
    func hostResumeNoOpWhenActive() async throws {
        let listener = FakeHostListener()
        let session = HostSession(
            identity: .makeTest(nickname: "Host"),
            secret: makeSecret(),
            listener: listener,
            configuration: .listenerRestart
        )
        let probe = EventProbe<SessionEvent>(stream: session.events)

        Task { await session.start() }
        listener.emitReady()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Нет активного перезапуска — resumeAfterForeground должен быть no-op
        await session.resumeAfterForeground()
        try await Task.sleep(for: .milliseconds(200))

        // Listener не перезапускался
        #expect(listener.startCount == 1)

        await session.end()
    }

    // MARK: - Тест 3: клиент — resumeAfterForeground пропускает паузу переподключения

    @Test("Client: resumeAfterForeground skips reconnect backoff")
    func clientResumeSkipsBackoff() async throws {
        let secret = makeSecret()
        let invite = RoomInvite(version: RoomInvite.currentVersion,
                                serviceName: UUID().uuidString,
                                roomKey: secret.roomKeyData)
        let listener = FakeHostListener()
        let connector = FakeClientConnector(listener: listener)
        let session = ClientSession(
            identity: .makeTest(nickname: "Client"),
            invite: invite,
            secret: secret,
            connector: connector,
            configuration: longBackoffConfig
        )
        let probe = EventProbe<SessionEvent>(stream: session.events)

        // Хэндшейк до .active
        Task { await session.start() }
        let serverConn = try await waitForServer(at: 1, in: connector)
        let welcome = HostWelcome(status: "success", sessionID: UUID(),
                                  hostPermanentPeerID: UUID(), hostNickname: "Host",
                                  participants: [])
        try await serverConn.send(.hostWelcome(welcome))
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Мягкий разрыв → reconnecting
        serverConn.emit(.viability(false))
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.reconnecting) = $0 { return true }; return false
        }

        // Без resumeAfterForeground ждать 30 с; с ним — немедленная попытка
        await session.resumeAfterForeground()

        let deadline = ContinuousClock.now + .seconds(5)
        while connector.serverConnections.count < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(connector.serverConnections.count >= 2, "resumeAfterForeground should bypass reconnect backoff")
    }

    // MARK: - Тест 4: клиент — resumeAfterForeground no-op когда сессия активна

    @Test("Client: resumeAfterForeground is no-op when session is active")
    func clientResumeNoOpWhenActive() async throws {
        let secret = makeSecret()
        let invite = RoomInvite(version: RoomInvite.currentVersion,
                                serviceName: UUID().uuidString,
                                roomKey: secret.roomKeyData)
        let listener = FakeHostListener()
        let connector = FakeClientConnector(listener: listener)
        let session = ClientSession(
            identity: .makeTest(nickname: "Client"),
            invite: invite,
            secret: secret,
            connector: connector,
            configuration: .reliability
        )
        let probe = EventProbe<SessionEvent>(stream: session.events)

        Task { await session.start() }
        let serverConn = try await waitForServer(at: 1, in: connector)
        let welcome = HostWelcome(status: "success", sessionID: UUID(),
                                  hostPermanentPeerID: UUID(), hostNickname: "Host",
                                  participants: [])
        try await serverConn.send(.hostWelcome(welcome))
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // No-op: нет переподключения
        await session.resumeAfterForeground()
        try await Task.sleep(for: .milliseconds(200))

        // Соединение только одно — лишнего не создано
        #expect(connector.serverConnections.count == 1)
        // Сессия остаётся .active
        #expect(!probe.events.contains {
            if case .stateChanged(.reconnecting) = $0 { return true }; return false
        })
    }
}

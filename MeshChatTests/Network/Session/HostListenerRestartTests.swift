// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

/// `@MainActor` нужен потому, что с `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
/// инициализатор актора `HostSession` выводится как `@MainActor`-изолированный.
@MainActor
@Suite("HostListenerRestartTests", .serialized, .timeLimit(.minutes(1)))
struct HostListenerRestartTests {

    // MARK: - Вспомогательные методы

    func makeSecret() -> any RoomSecret {
        try! RoomCredentials(roomKeyData: Data(repeating: 0xAB, count: 32))
    }

    func makeSession(
        identity: LocalIdentity = .makeTest(nickname: "Host"),
        configuration: NetworkConfiguration = .listenerRestart
    ) -> (HostSession, FakeHostListener) {
        let listener = FakeHostListener()
        let session = HostSession(
            identity: identity,
            secret: makeSecret(),
            listener: listener,
            configuration: configuration
        )
        return (session, listener)
    }

    // MARK: - Тест 1: перезапуск после сбоя

    @Test("Listener failure after active triggers restart; session stays .active")
    func restartAfterFailure() async throws {
        let (session, listener) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)

        Task { await session.start() }
        listener.emitReady()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Listener падает после active → должен перезапуститься
        listener.emitFailure(.other("link down"))

        let deadline = ContinuousClock.now + .seconds(5)
        while listener.startCount < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(listener.startCount == 2, "Listener should restart after failure")

        // Сессия не завершилась
        #expect(!probe.events.contains {
            if case .stateChanged(.ended) = $0 { return true }; return false
        })

        // Новый listener становится ready — сессия остаётся active
        listener.emitReady()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!probe.events.contains {
            if case .stateChanged(.ended) = $0 { return true }; return false
        })

        await session.end()
    }

    // MARK: - Тест 2: повторная попытка когда start() бросает ошибку

    @Test("Listener restart retries after start() throws once")
    func restartRetryOnStartThrow() async throws {
        let (session, listener) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)

        Task { await session.start() }
        listener.emitReady()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Следующий start() бросит ошибку → цикл должен продолжить и попробовать ещё раз
        listener.setNextStartThrows()
        listener.emitFailure(.other("link down"))

        // Ждём startCount == 2: первая попытка броска (счётчик не растёт),
        // вторая попытка успешна (счётчик 1 → 2)
        let deadline = ContinuousClock.now + .seconds(5)
        while listener.startCount < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(listener.startCount >= 2, "Should retry after start() throw")

        // Сессия не завершилась
        #expect(!probe.events.contains {
            if case .stateChanged(.ended) = $0 { return true }; return false
        })

        await session.end()
    }

    // MARK: - Тест 3: localNetworkDenied после active → ended

    @Test("localNetworkDenied after active ends session (no restart)")
    func localNetworkDeniedAfterActive() async throws {
        let (session, listener) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)

        Task { await session.start() }
        listener.emitReady()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        listener.emitFailure(.localNetworkDenied)

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.localNetworkDenied)) = $0 { return true }; return false
        }

        // Перезапуска не было — startCount == 1
        #expect(listener.startCount == 1, "No restart on localNetworkDenied")
    }

    // MARK: - Тест 4: регрессионный — сбой до .ready завершает сессию

    @Test("Listener failure before first ready ends session (no restart)")
    func failureBeforeReadyEndsSession() async throws {
        let (session, listener) = makeSession()
        let probe = EventProbe<SessionEvent>(stream: session.events)

        Task { await session.start() }

        // Сбой до первого .ready
        listener.emitFailure(.other("init failure"))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended) = $0 { return true }; return false
        }

        // Перезапуска не было
        try await Task.sleep(for: .milliseconds(200))
        #expect(listener.startCount == 1, "No restart on pre-ready failure")
    }

    // MARK: - Тест 5: end() во время паузы backoff

    @Test("end() during restart backoff cancels task; stop() called exactly once")
    func endDuringRestartBackoff() async throws {
        // Длинный backoff — гарантируем, что end() застаёт задачу в паузе
        let longBackoffConfig = NetworkConfiguration(
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
        let (session, listener) = makeSession(configuration: longBackoffConfig)
        let probe = EventProbe<SessionEvent>(stream: session.events)

        Task { await session.start() }
        listener.emitReady()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Триггер перезапуска — задача уходит в 30-секундную паузу
        listener.emitFailure(.other("link down"))
        // Даём задаче войти в Task.sleep
        try await Task.sleep(for: .milliseconds(100))

        await session.end()

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.leftByUser)) = $0 { return true }; return false
        }

        // stop() вызван ровно один раз (из _end()), перезапуска не было
        #expect(listener.stopCount == 1)
        #expect(listener.startCount == 1)
    }

    // MARK: - Тест 6: подключённый клиент переживает перезапуск listener'а

    @Test("Connected client survives listener failure and restart")
    func connectedClientSurvivesListenerRestart() async throws {
        let secret = makeSecret()
        let listener = FakeHostListener()
        let session = HostSession(
            identity: .makeTest(nickname: "Host"),
            secret: secret,
            listener: listener,
            configuration: .listenerRestart
        )
        let probe = EventProbe<SessionEvent>(stream: session.events)

        Task { await session.start() }
        listener.emitReady()
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Подключаем клиента
        let (clientConn, serverConn) = FakePeerConnection.makePair()
        listener.accept(serverConn)
        try await playClient(connection: clientConn, identity: .makeTest(nickname: "Alice"),
                             secret: secret)
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .participantJoined = $0 { return true }; return false
        }

        // Listener падает — клиент должен остаться в сессии
        listener.emitFailure(.other("link down"))

        let deadline = ContinuousClock.now + .seconds(5)
        while listener.startCount < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(listener.startCount == 2)

        // Хост шлёт сообщение — должно дойти до клиента и появиться в событиях сессии
        let msg = try await session.send(text: "still alive")
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .messageReceived(let m) = $0 { return m.id == msg.id }; return false
        }

        // .participantLeft не было — клиент не потерян
        #expect(!probe.events.contains {
            if case .participantLeft = $0 { return true }; return false
        })

        await session.end()
    }
}

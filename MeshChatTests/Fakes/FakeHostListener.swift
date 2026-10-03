// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковый listener для юнит-тестов сессий (§7.8).
///
/// Поддерживает многократный вызов `start()` — каждый создаёт новый поток событий.
/// Все мутируемые поля защищены `NSLock` — отсюда `@unchecked Sendable`.
final class FakeHostListener: HostListening, @unchecked Sendable {

    // MARK: - Внутреннее состояние

    private let lock = NSLock()
    private var continuation: AsyncStream<ListenerEvent>.Continuation?
    private var pendingEvents: [ListenerEvent] = []

    private var _startCount: Int = 0
    private var _stopCount: Int = 0
    private var _serviceNameHistory: [String] = []
    private var _securityHistory: [ChannelSecurity] = []
    private var _nextStartThrows: Bool = false

    // MARK: - Наблюдаемые свойства для тестов

    /// Количество успешных вызовов `start()`.
    nonisolated var startCount: Int { lock.withLock { _startCount } }
    /// Количество вызовов `stop()`.
    nonisolated var stopCount: Int { lock.withLock { _stopCount } }
    /// Имя сервиса последнего вызова `start`.
    nonisolated var lastServiceName: String? { lock.withLock { _serviceNameHistory.last } }
    /// Параметры безопасности последнего вызова `start`.
    nonisolated var lastSecurity: ChannelSecurity? { lock.withLock { _securityHistory.last } }
    /// История имён сервиса по всем вызовам `start`.
    nonisolated var serviceNameHistory: [String] { lock.withLock { _serviceNameHistory } }
    /// История параметров безопасности по всем вызовам `start`.
    nonisolated var securityHistory: [ChannelSecurity] { lock.withLock { _securityHistory } }
    /// Обратная совместимость.
    nonisolated var stopCalled: Bool { lock.withLock { _stopCount > 0 } }

    // MARK: - HostListening

    nonisolated func start(serviceName: String, security: ChannelSecurity) throws -> AsyncStream<ListenerEvent> {
        // Следующий start бросает ошибку (режим для тестов повторных попыток).
        let shouldThrow = lock.withLock { () -> Bool in
            if _nextStartThrows { _nextStartThrows = false; return true }
            return false
        }
        if shouldThrow { throw FakeListenerError.simulatedStartFailure }

        var cont: AsyncStream<ListenerEvent>.Continuation!
        let stream = AsyncStream<ListenerEvent> { cont = $0 }

        let buffered = lock.withLock { () -> [ListenerEvent] in
            continuation = cont
            _serviceNameHistory.append(serviceName)
            _securityHistory.append(security)
            _startCount += 1
            let b = pendingEvents
            pendingEvents.removeAll()
            return b
        }
        for event in buffered {
            _ = cont.yield(event)
        }
        return stream
    }

    nonisolated func stop() {
        let cont = lock.withLock { () -> AsyncStream<ListenerEvent>.Continuation? in
            _stopCount += 1
            let c = continuation
            continuation = nil
            return c
        }
        cont?.finish()
    }

    // MARK: - Вспомогательные методы для тестов

    /// Следующий вызов `start()` бросит `FakeListenerError.simulatedStartFailure`.
    nonisolated func setNextStartThrows() {
        lock.withLock { _nextStartThrows = true }
    }

    /// Эмитит `.ready(port:)`. Если `start()` ещё не вызван — буферизует событие.
    nonisolated func emitReady(port: UInt16 = 0) {
        emitOrBuffer(.ready(port: port))
    }

    /// Эмитит `.failed(_:)` и завершает поток. Если `start()` ещё не вызван — буферизует.
    nonisolated func emitFailure(_ issue: NetworkIssue = .other("fake failure")) {
        let cont = lock.withLock { () -> AsyncStream<ListenerEvent>.Continuation? in
            if let c = continuation {
                continuation = nil
                return c
            } else {
                pendingEvents.append(.failed(issue))
                return nil
            }
        }
        if let cont {
            _ = cont.yield(.failed(issue))
            cont.finish()
        }
    }

    /// Передаёт входящее соединение. Если `start()` ещё не вызван — буферизует.
    nonisolated func accept(_ connection: any PeerConnection) {
        emitOrBuffer(.incoming(connection))
    }

    // MARK: - Приватный хелпер

    nonisolated private func emitOrBuffer(_ event: ListenerEvent) {
        lock.withLock {
            if let cont = continuation {
                _ = cont.yield(event)
            } else {
                pendingEvents.append(event)
            }
        }
    }
}

// MARK: - Ошибки фейка

enum FakeListenerError: Error, Equatable {
    case simulatedStartFailure
}

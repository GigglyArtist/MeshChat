// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковый listener для юнит-тестов сессий (§7.8).
///
/// События, эмитированные до вызова `start()`, буферизуются и доставляются
/// сразу после того, как сессия вызовет `start()` и установит continuation.
///
/// Все мутируемые поля защищены `NSLock` — отсюда `@unchecked Sendable`.
final class FakeHostListener: HostListening, @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: AsyncStream<ListenerEvent>.Continuation?
    private var pendingEvents: [ListenerEvent] = []
    private var _stopCalled = false
    private var _lastServiceName: String?
    private var _lastSecurity: ChannelSecurity?

    /// Был ли вызван `stop()`.
    nonisolated var stopCalled: Bool { lock.withLock { _stopCalled } }
    /// Имя сервиса последнего вызова `start`.
    nonisolated var lastServiceName: String? { lock.withLock { _lastServiceName } }
    /// Параметры безопасности последнего вызова `start`.
    nonisolated var lastSecurity: ChannelSecurity? { lock.withLock { _lastSecurity } }

    // MARK: - HostListening

    nonisolated func start(serviceName: String, security: ChannelSecurity) throws -> AsyncStream<ListenerEvent> {
        var cont: AsyncStream<ListenerEvent>.Continuation!
        let stream = AsyncStream<ListenerEvent> { cont = $0 }
        // Сохраняем continuation и воспроизводим буферизованные события.
        let buffered = lock.withLock { () -> [ListenerEvent] in
            continuation = cont
            _lastServiceName = serviceName
            _lastSecurity = security
            _stopCalled = false
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
            _stopCalled = true
            let c = continuation
            continuation = nil
            return c
        }
        cont?.finish()
    }

    // MARK: - Вспомогательные методы для тестов

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

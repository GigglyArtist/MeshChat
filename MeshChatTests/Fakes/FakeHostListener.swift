// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковый listener для юнит-тестов сессий (§7.8).
///
/// Все мутируемые поля защищены `NSLock` — отсюда `@unchecked Sendable`.
final class FakeHostListener: HostListening, @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: AsyncStream<ListenerEvent>.Continuation?
    private var _stopCalled = false
    private var _lastServiceName: String?
    private var _lastSecurity: ChannelSecurity?

    /// Сколько раз был вызван `stop()`.
    var stopCalled: Bool { lock.withLock { _stopCalled } }
    /// Имя сервиса, переданное последнему вызову `start`.
    var lastServiceName: String? { lock.withLock { _lastServiceName } }
    /// Параметры безопасности, переданные последнему вызову `start`.
    var lastSecurity: ChannelSecurity? { lock.withLock { _lastSecurity } }

    // MARK: - HostListening

    nonisolated func start(serviceName: String, security: ChannelSecurity) throws -> AsyncStream<ListenerEvent> {
        var cont: AsyncStream<ListenerEvent>.Continuation!
        let stream = AsyncStream<ListenerEvent> { cont = $0 }
        lock.withLock {
            continuation = cont
            _lastServiceName = serviceName
            _lastSecurity = security
            _stopCalled = false
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

    /// Имитирует переход listener'а в готовность на указанном порту.
    func emitReady(port: UInt16 = 0) {
        lock.withLock { continuation?.yield(.ready(port: port)) }
    }

    /// Имитирует ошибку listener'а.
    func emitFailure(_ issue: NetworkIssue = .other("fake failure")) {
        let cont = lock.withLock { () -> AsyncStream<ListenerEvent>.Continuation? in
            let c = continuation
            continuation = nil
            return c
        }
        cont?.yield(.failed(issue))
        cont?.finish()
    }

    /// Передаёт входящее соединение в поток listener'а.
    func accept(_ connection: any PeerConnection) {
        lock.withLock { continuation?.yield(.incoming(connection)) }
    }
}

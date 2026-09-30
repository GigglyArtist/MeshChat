// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Прослойка над реальным `BonjourHostListener` для интеграционных тестов сессий.
///
/// Перехватывает события listener'а и сохраняет порт при получении `.ready`,
/// позволяя тесту получить его через `waitForPort()` до того, как `ClientSession` создана.
///
/// Все мутируемые поля защищены `NSLock` — отсюда `@unchecked Sendable`.
final class ListenerTap: HostListening, @unchecked Sendable {

    private let configuration: NetworkConfiguration
    private let lock = NSLock()
    private var _port: UInt16? = nil
    private var _inner: BonjourHostListener? = nil
    private var _tapTask: Task<Void, Never>? = nil

    nonisolated init(configuration: NetworkConfiguration = .loopback) {
        self.configuration = configuration
    }

    // MARK: - HostListening

    nonisolated func start(serviceName: String, security: ChannelSecurity) throws -> AsyncStream<ListenerEvent> {
        let inner = BonjourHostListener(configuration: configuration)
        let upstream = try inner.start(serviceName: serviceName, security: security)
        lock.withLock { _inner = inner }

        let (stream, cont) = AsyncStream.makeStream(of: ListenerEvent.self)

        let task = Task { [weak self] in
            for await event in upstream {
                if case .ready(let port) = event {
                    self?.lock.withLock { self?._port = port }
                }
                _ = cont.yield(event)
            }
            cont.finish()
        }
        lock.withLock { _tapTask = task }
        return stream
    }

    nonisolated func stop() {
        let (inner, task) = lock.withLock { (_inner, _tapTask) }
        inner?.stop()
        task?.cancel()
    }

    // MARK: - Доступ к порту

    /// Ждёт, пока listener не перейдёт в `.ready`, и возвращает назначенный порт.
    nonisolated func waitForPort(timeout: Duration = .seconds(10)) async throws -> UInt16 {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let p = lock.withLock({ _port }) { return p }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ListenerTapError.portTimeout
    }
}

/// Ошибки `ListenerTap`.
nonisolated enum ListenerTapError: Error {
    case portTimeout
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Режим работы `FakeClientConnector` (§9.6).
enum ConnectionMode {
    /// Каждое новое соединение переходит в `.ready` при `start()`.
    case reachable
    /// Новые соединения никогда не переходят в `.ready` (хост недоступен).
    case unreachable
}

/// Фейковый клиентский коннектор для юнит-тестов сессий (§7.8).
///
/// При `makeConnection` создаёт пару `FakePeerConnection`: клиентский конец возвращает
/// вызывающему (ClientSession), серверный конец передаёт в связанный `FakeHostListener`.
///
/// Все мутируемые поля защищены `NSLock` — отсюда `@unchecked Sendable`.
final class FakeClientConnector: ClientConnecting, @unchecked Sendable {

    private let listener: FakeHostListener
    private let lock = NSLock()
    private var _mode: ConnectionMode
    /// Клиентские концы пар в порядке создания.
    private var _clientConnections: [FakePeerConnection] = []
    /// Серверные концы пар в порядке создания.
    private var _serverConnections: [FakePeerConnection] = []

    /// Все клиентские концы пар в порядке вызовов `makeConnection`.
    var clientConnections: [FakePeerConnection] { lock.withLock { _clientConnections } }
    /// Все серверные концы пар в порядке вызовов `makeConnection`.
    var serverConnections: [FakePeerConnection] { lock.withLock { _serverConnections } }
    /// Число созданных соединений.
    var connectionCount: Int { lock.withLock { _clientConnections.count } }

    /// - Parameters:
    ///   - listener: связанный `FakeHostListener`, которому передаётся серверный конец пары.
    ///   - mode: начальный режим; по умолчанию `.reachable`.
    init(listener: FakeHostListener, mode: ConnectionMode = .reachable) {
        self.listener = listener
        self._mode = mode
    }

    /// Переключает режим во время теста (например, с `.reachable` на `.unreachable`).
    func setMode(_ mode: ConnectionMode) {
        lock.withLock { _mode = mode }
    }

    // MARK: - ClientConnecting

    nonisolated func makeConnection(serviceName: String, security: ChannelSecurity) -> any PeerConnection {
        let startReady: Bool = lock.withLock {
            switch _mode {
            case .reachable: return true
            case .unreachable: return false
            }
        }
        let (client, server) = FakePeerConnection.makePair(startReady: startReady)
        lock.withLock {
            _clientConnections.append(client)
            _serverConnections.append(server)
        }
        listener.accept(server)
        return client
    }
}

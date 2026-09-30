// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковый клиентский коннектор для юнит-тестов сессий (§7.8).
///
/// При `makeConnection` создаёт пару `FakePeerConnection`: клиентский конец возвращает
/// вызывающему (ClientSession), серверный конец передаёт в связанный `FakeHostListener`.
///
/// Все мутируемые поля защищены `NSLock` — отсюда `@unchecked Sendable`.
final class FakeClientConnector: ClientConnecting, @unchecked Sendable {

    private let listener: FakeHostListener
    /// Если `true`, созданные соединения **никогда** не переходят в `.ready`.
    private let neverReady: Bool

    private let lock = NSLock()
    /// Клиентские концы пар в порядке создания.
    private var _clientConnections: [FakePeerConnection] = []

    /// Все клиентские концы пар в порядке вызовов `makeConnection`.
    var clientConnections: [FakePeerConnection] { lock.withLock { _clientConnections } }

    /// - Parameters:
    ///   - listener: связанный `FakeHostListener`, которому передаётся серверный конец пары.
    ///   - neverReady: если `true`, `start()` не эмитит `.ready`.
    init(listener: FakeHostListener, neverReady: Bool = false) {
        self.listener = listener
        self.neverReady = neverReady
    }

    // MARK: - ClientConnecting

    nonisolated func makeConnection(serviceName: String, security: ChannelSecurity) -> any PeerConnection {
        let (client, server) = FakePeerConnection.makePair(startReady: !neverReady)
        lock.withLock { _clientConnections.append(client) }
        listener.accept(server)
        return client
    }
}

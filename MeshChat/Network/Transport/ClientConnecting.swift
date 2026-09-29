// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Создаёт исходящее соединение к Bonjour-сервису хоста (§7.3).
protocol ClientConnecting: Sendable {

    /// Создаёт и возвращает незапущенное соединение.
    ///
    /// `start()` вызывает сессия — это позволяет подписаться на `events` до первого события.
    func makeConnection(serviceName: String, security: ChannelSecurity) -> any PeerConnection
}

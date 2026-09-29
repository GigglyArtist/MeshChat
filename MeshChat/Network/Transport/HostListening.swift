// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Публикует Bonjour-сервис и принимает входящие соединения (§7.3).
protocol HostListening: AnyObject, Sendable {

    /// Публикует `<serviceName>.<serviceType>` и возвращает поток событий listener'а.
    ///
    /// - Throws: `NetworkError.listenerFailed` при повторном вызове у работающего listener'а.
    nonisolated func start(serviceName: String, security: ChannelSecurity) throws -> AsyncStream<ListenerEvent>

    /// Останавливает listener. Завершает поток событий. Идемпотентен.
    ///
    /// После `stop()` можно снова вызвать `start()` с тем же `serviceName` (ADR-11).
    nonisolated func stop()
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Событие от `HostListening` (§7.3).
nonisolated enum ListenerEvent: Sendable {
    /// Listener готов; `port` — фактический TCP-порт (используется в тестах через 127.0.0.1).
    case ready(port: UInt16)
    /// Listener остановлен из-за ошибки (включая `.waiting(localNetworkDenied)`).
    case failed(NetworkIssue)
    /// Новое входящее соединение, ещё не запущенное; `start()` вызывает сессия.
    case incoming(any PeerConnection)
}

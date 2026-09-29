// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Состояние одного `PeerConnection` (§7.3).
nonisolated enum ConnectionState: Sendable, Equatable {
    /// Соединение устанавливается.
    case preparing
    /// Соединение готово к обмену данными.
    case ready
    /// Путь временно недоступен; может восстановиться само.
    case waiting(NetworkIssue)
    /// Соединение окончательно потеряно; экземпляр не восстановится.
    case failed(NetworkIssue)
    /// Соединение закрыто явно (`cancel()`).
    case cancelled
}

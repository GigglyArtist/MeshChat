// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Сессия чата в том виде, в котором её видит приложение.
nonisolated struct ChatSessionInfo: Sendable, Hashable, Identifiable {
    /// `sessionID` хоста — одинаков у всех участников комнаты.
    let id: UUID
    /// Момент создания сессии.
    let createdAt: Date
    /// Момент завершения; `nil` — сессия ещё активна.
    var endedAt: Date?
    /// Роль локального устройства в этой сессии.
    let role: SessionRole
    /// Список участников (без локального пользователя), отсортированный по никнейму.
    var participants: [PeerProfile]
}

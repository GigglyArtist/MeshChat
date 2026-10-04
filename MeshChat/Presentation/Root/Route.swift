// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Навигационные маршруты из главного экрана (§12.1).
enum Route: Hashable {
    case createRoom
    case joinRoom
    /// Активный чат; путь заменяется на `[.chat(…)]` после создания/входа.
    case chat(ChatRoute)
    /// Список собеседников из истории.
    case history
    /// Список сессий с конкретным собеседником.
    case peerHistory(PeerProfile)
    /// Переписка одной сессии (только чтение).
    case transcript(sessionID: UUID)
}

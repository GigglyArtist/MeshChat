// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Причина ухода участника из комнаты (§5.1).
nonisolated enum LeaveReason: String, Sendable {
    /// Участник вышел сам.
    case left
    /// Грейс-период истёк — связь не восстановилась.
    case connectionLost
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Роль локального устройства в конкретной сессии. Raw value хранится в Core Data.
nonisolated enum SessionRole: Int16, Sendable {
    /// Устройство создало комнату (запускало NWListener).
    case host = 0
    /// Устройство вошло в комнату по QR-коду.
    case client = 1
}

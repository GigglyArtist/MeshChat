// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Служебное уведомление о событии в комнате — отображается в ленте как системная строка (§12.1.1).
nonisolated enum RoomNotice: Sendable, Equatable {
    /// Участник с указанным никнеймом вошёл в комнату.
    case joined(nickname: String)
    /// Участник с указанным никнеймом покинул комнату.
    case left(nickname: String, reason: LeaveReason)
}

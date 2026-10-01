// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Ошибки при создании или входе в комнату (§11).
nonisolated enum RoomError: Error, Sendable, Equatable {
    /// Онбординг не пройден — ник отсутствует; комнату создать нельзя.
    case nicknameMissing
}

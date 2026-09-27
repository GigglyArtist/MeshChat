// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Полезная нагрузка пакетов `ping` и `pong` (§8.3).
nonisolated struct HeartbeatPayload: Codable, Sendable, Equatable {
    /// Время отправки `ping`; хост копирует значение в `pong` без изменений.
    let sentAt: Date
}

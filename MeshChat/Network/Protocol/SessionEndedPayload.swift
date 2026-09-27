// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Пакет завершения сессии, который хост рассылает всем клиентам (§8.3).
nonisolated struct SessionEndedPayload: Codable, Sendable, Equatable {
    let reason: String
}

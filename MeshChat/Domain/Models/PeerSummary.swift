// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Агрегированная информация о собеседнике для экрана «История» (§11).
nonisolated struct PeerSummary: Sendable, Hashable, Identifiable {
    /// Идентификатор — PermanentPeerID собеседника.
    var id: UUID { profile.id }
    /// Профиль собеседника с последним известным ником.
    let profile: PeerProfile
    /// Количество сохранённых сессий с этим человеком.
    let sessionCount: Int
    /// `createdAt` самой свежей сессии; `nil`, если сессий нет.
    let lastSessionAt: Date?
}

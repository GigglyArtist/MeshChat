// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Участник, известный приложению. `id` — это PermanentPeerID устройства.
nonisolated struct PeerProfile: Sendable, Hashable, Identifiable {
    /// PermanentPeerID устройства.
    let id: UUID
    /// Отображаемое имя. Может меняться между сессиями.
    var nickname: String
}

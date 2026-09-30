// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Идентификатор локального устройства в сессии (§5.1).
nonisolated struct LocalIdentity: Sendable, Hashable {
    /// Постоянный UUID устройства.
    let peerID: UUID
    /// Отображаемое имя пользователя.
    let nickname: String

    /// Профиль для передачи другим участникам.
    var profile: PeerProfile { PeerProfile(id: peerID, nickname: nickname) }
}

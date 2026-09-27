// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// DTO профиля участника в пакетах `participantJoined` и `hostWelcome` (§8.3).
nonisolated struct PeerPayload: Codable, Sendable, Equatable {
    let permanentPeerID: UUID
    let nickname: String
}

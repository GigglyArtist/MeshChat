// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Уведомление об уходе участника, рассылаемое хостом (§8.3).
nonisolated struct ParticipantLeftPayload: Codable, Sendable, Equatable {
    let permanentPeerID: UUID
    /// Raw value из `LeaveReason`; неизвестная строка → `.connectionLost` (§8.6).
    let reason: String
}

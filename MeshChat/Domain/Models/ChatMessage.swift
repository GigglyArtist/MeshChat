// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Одно текстовое сообщение чата.
nonisolated struct ChatMessage: Sendable, Hashable, Identifiable {
    /// Уникальный идентификатор сообщения.
    let id: UUID
    /// Текст сообщения.
    let text: String
    /// Время, проставленное отправителем в момент отправки.
    let timestamp: Date
    /// PermanentPeerID отправителя (своего устройства или чужого).
    let senderID: UUID
}

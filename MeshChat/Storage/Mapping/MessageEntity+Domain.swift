// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import CoreData

extension MessageEntity {
    /// Преобразует сущность Core Data в доменное сообщение.
    nonisolated func toDomain() -> ChatMessage {
        ChatMessage(id: id, text: text, timestamp: timestamp, senderID: senderID)
    }
}

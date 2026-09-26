// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import CoreData

/// Core Data-сущность сессии чата. Соответствует сущности «ChatSession» в модели.
@objc(ChatSessionEntity)
nonisolated class ChatSessionEntity: NSManagedObject {
    /// sessionID хоста — одинаков у всех участников комнаты.
    @NSManaged var id: UUID
    /// Момент создания сессии.
    @NSManaged var createdAt: Date
    /// Момент завершения; `nil` — сессия ещё активна.
    @NSManaged var endedAt: Date?
    /// Хранимое raw-значение роли (`SessionRole.rawValue`).
    @NSManaged var roleRaw: Int16
    /// Сообщения сессии. Удаляются каскадно вместе с сессией (R13).
    @NSManaged var messages: Set<MessageEntity>
    /// Участники сессии (без локального пользователя).
    @NSManaged var participants: Set<PeerEntity>

    /// Роль локального устройства в этой сессии.
    var role: SessionRole {
        SessionRole(rawValue: roleRaw) ?? .host
    }
}

extension ChatSessionEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ChatSessionEntity> {
        NSFetchRequest<ChatSessionEntity>(entityName: "ChatSession")
    }
}

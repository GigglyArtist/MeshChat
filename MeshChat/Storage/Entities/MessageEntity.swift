// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import CoreData

/// Core Data-сущность сообщения. Соответствует сущности «Message» в модели.
@objc(MessageEntity)
nonisolated class MessageEntity: NSManagedObject {
    /// Уникальный идентификатор сообщения (защита от дублей при ретрансляции).
    @NSManaged var id: UUID
    /// Текст сообщения.
    @NSManaged var text: String
    /// Время, проставленное отправителем.
    @NSManaged var timestamp: Date
    /// PermanentPeerID отправителя.
    @NSManaged var senderID: UUID
    /// Сессия, к которой относится сообщение. Обязательна: сообщение без сессии не существует.
    @NSManaged var session: ChatSessionEntity
}

extension MessageEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<MessageEntity> {
        NSFetchRequest<MessageEntity>(entityName: "Message")
    }
}

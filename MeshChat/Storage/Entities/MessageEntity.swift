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
    /// Сессия, к которой относится сообщение. Optional в модели (ограничение Core Data §10.2);
    /// инвариант «без сессии нет сообщения» гарантирует StorageManager.
    @NSManaged var session: ChatSessionEntity?
}

nonisolated extension MessageEntity {
    /// Имя сущности в модели Core Data.
    nonisolated static let entityName = "Message"

    @nonobjc class func fetchRequest() -> NSFetchRequest<MessageEntity> {
        NSFetchRequest<MessageEntity>(entityName: entityName)
    }
}

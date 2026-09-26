// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import CoreData

/// Core Data-сущность участника. Соответствует сущности «Peer» в модели.
@objc(PeerEntity)
nonisolated class PeerEntity: NSManagedObject {
    /// PermanentPeerID устройства.
    @NSManaged var id: UUID
    /// Последний известный никнейм участника.
    @NSManaged var nickname: String
    /// Время последнего появления в сессии. Используется для сортировки списка собеседников.
    @NSManaged var lastSeenAt: Date
    /// Все сессии, в которых участвовал этот человек.
    @NSManaged var sessions: Set<ChatSessionEntity>
}

extension PeerEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PeerEntity> {
        NSFetchRequest<PeerEntity>(entityName: "Peer")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import CoreData

nonisolated extension ChatSessionEntity {
    /// Преобразует сущность Core Data в доменное описание сессии.
    /// Участники сортируются по никнейму для стабильного порядка.
    nonisolated func toDomain() -> ChatSessionInfo {
        let sortedParticipants = participants
            .sorted { $0.nickname < $1.nickname }
            .map { $0.toDomain() }
        return ChatSessionInfo(
            id: id,
            createdAt: createdAt,
            endedAt: endedAt,
            role: role,
            participants: sortedParticipants
        )
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import CoreData

nonisolated extension PeerEntity {
    /// Преобразует сущность Core Data в доменный профиль участника.
    nonisolated func toDomain() -> PeerProfile {
        PeerProfile(id: id, nickname: nickname)
    }
}

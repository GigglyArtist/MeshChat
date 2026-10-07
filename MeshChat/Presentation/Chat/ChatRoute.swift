// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Обёртка `any ActiveRoomHandling` для навигационного стека (§12.1).
///
/// Равенство и хэш определяются идентичностью объекта (`ObjectIdentifier`),
/// т.к. `ActiveRoomHandling: AnyObject`.
struct ChatRoute: Hashable {

    let room: any ActiveRoomHandling
    /// Приглашение для повторного входа; только у клиента (§12.1.1).
    let rejoinInvite: RoomInvite?

    init(room: any ActiveRoomHandling, rejoinInvite: RoomInvite? = nil) {
        self.room = room
        self.rejoinInvite = rejoinInvite
    }

    static func == (lhs: ChatRoute, rhs: ChatRoute) -> Bool {
        ObjectIdentifier(lhs.room) == ObjectIdentifier(rhs.room)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(room))
    }
}

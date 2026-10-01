// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

#if DEBUG
import Foundation

/// Реализация `RoomServicing` для SwiftUI Previews: возвращает `PreviewActiveRoom`.
nonisolated struct PreviewRoomService: RoomServicing {

    nonisolated func createRoom(password: String) async throws -> any ActiveRoomHandling {
        let roomKey = Data(repeating: 0xAB, count: 32)
        let invite = RoomInvite(
            version: RoomInvite.currentVersion,
            serviceName: UUID().uuidString,
            roomKey: roomKey
        )
        return PreviewActiveRoom(role: .host, invite: invite)
    }

    nonisolated func joinRoom(invite: RoomInvite) async throws -> any ActiveRoomHandling {
        return PreviewActiveRoom(role: .client, invite: nil)
    }
}
#endif

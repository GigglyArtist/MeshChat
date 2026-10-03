// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

#if DEBUG
import Foundation

/// Статичная комната для SwiftUI Previews: события не генерируются, отправка — no-op.
///
/// Continuation хранится, чтобы поток не завершался сразу: Preview получает
/// стабильную комнату без реальных сетевых событий.
nonisolated final class PreviewActiveRoom: ActiveRoomHandling {

    nonisolated let role: SessionRole
    nonisolated let localPeerID: UUID
    nonisolated let invite: RoomInvite?
    nonisolated let events: AsyncStream<RoomEvent>

    // Хранится, чтобы поток оставался открытым на протяжении жизни объекта.
    private let _continuation: AsyncStream<RoomEvent>.Continuation

    init(role: SessionRole = .host, invite: RoomInvite? = nil) {
        self.role = role
        self.localPeerID = UUID()
        self.invite = invite
        var cont: AsyncStream<RoomEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self._continuation = cont
    }

    nonisolated func send(text: String) async throws {}
    nonisolated func leave() async {}
    nonisolated func appDidBecomeActive() async {}
}
#endif

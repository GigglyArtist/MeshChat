// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковый `RoomServicing` для тестов UI-слоя.
nonisolated struct FakeRoomService: RoomServicing {

    let createdRoom: FakeActiveRoom
    let joinedRoom: FakeActiveRoom
    let createError: RoomError?
    let joinError: RoomError?

    init(
        createRoom: FakeActiveRoom = FakeActiveRoom(role: .host),
        joinRoom: FakeActiveRoom = FakeActiveRoom(role: .client),
        createError: RoomError? = nil,
        joinError: RoomError? = nil
    ) {
        self.createdRoom = createRoom
        self.joinedRoom = joinRoom
        self.createError = createError
        self.joinError = joinError
    }

    nonisolated func createRoom(password: String) async throws -> any ActiveRoomHandling {
        if let e = createError { throw e }
        return createdRoom
    }

    nonisolated func joinRoom(invite: RoomInvite) async throws -> any ActiveRoomHandling {
        if let e = joinError { throw e }
        return joinedRoom
    }
}

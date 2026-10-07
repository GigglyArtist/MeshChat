// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковый `RoomServicing` для тестов UI-слоя.
///
/// Мутируемый счётчик вызовов защищён `NSLock` — отсюда `@unchecked Sendable`.
final class FakeRoomService: RoomServicing, @unchecked Sendable {

    let createdRoom: FakeActiveRoom
    let joinedRoom: FakeActiveRoom
    let createError: RoomError?
    let joinError: RoomError?

    private let lock = NSLock()
    // nonisolated(unsafe): доступ из nonisolated-методов, безопасность гарантирует lock.
    nonisolated(unsafe) private var _joinCallCount = 0
    nonisolated(unsafe) private var _lastJoinedInvite: RoomInvite?

    var joinCallCount: Int { lock.withLock { _joinCallCount } }
    var lastJoinedInvite: RoomInvite? { lock.withLock { _lastJoinedInvite } }

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
        lock.withLock {
            _joinCallCount += 1
            _lastJoinedInvite = invite
        }
        if let e = joinError { throw e }
        return joinedRoom
    }
}

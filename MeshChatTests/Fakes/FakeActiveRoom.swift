// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковая реализация `ActiveRoomHandling` для тестов UI-слоя.
///
/// Все мутируемые поля защищены `NSLock` — отсюда `@unchecked Sendable`.
final class FakeActiveRoom: ActiveRoomHandling, @unchecked Sendable {

    // MARK: - ActiveRoomHandling

    nonisolated let role: SessionRole
    nonisolated let localPeerID: UUID
    nonisolated let invite: RoomInvite?
    nonisolated let events: AsyncStream<RoomEvent>

    // MARK: - Внутреннее состояние (защищены NSLock)

    // NSLock сериализует доступ; nonisolated(unsafe) подавляет проверку изоляции актора.
    private let lock = NSLock()
    // nonisolated(unsafe): доступ из nonisolated-методов, безопасность гарантирует lock.
    nonisolated(unsafe) private var continuation: AsyncStream<RoomEvent>.Continuation?
    nonisolated(unsafe) private var _sentTexts: [String] = []
    nonisolated(unsafe) private var _leaveCount: Int = 0
    /// Если задана — `send(text:)` бросает эту ошибку вместо успеха.
    // nonisolated(unsafe): доступ из nonisolated-методов, безопасность гарантирует lock.
    nonisolated(unsafe) var sendError: (any Error)?

    // MARK: - Наблюдаемые свойства для тестов

    var sentTexts: [String] { lock.withLock { _sentTexts } }
    var leaveCount: Int { lock.withLock { _leaveCount } }

    // MARK: - Инициализация

    init(role: SessionRole = .host,
         localPeerID: UUID = UUID(),
         invite: RoomInvite? = nil) {
        self.role = role
        self.localPeerID = localPeerID
        self.invite = invite
        var cont: AsyncStream<RoomEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // MARK: - Вспомогательные методы для тестов

    /// Отправляет событие в поток.
    func emit(_ event: RoomEvent) {
        lock.withLock { _ = continuation?.yield(event) }
    }

    /// Завершает поток событий.
    func finish() {
        lock.withLock { continuation?.finish(); continuation = nil }
    }

    // MARK: - ActiveRoomHandling

    nonisolated func send(text: String) async throws {
        let error: (any Error)? = lock.withLock {
            _sentTexts.append(text)
            return sendError
        }
        if let error { throw error }
    }

    nonisolated func leave() async {
        lock.withLock { _leaveCount += 1 }
    }
}

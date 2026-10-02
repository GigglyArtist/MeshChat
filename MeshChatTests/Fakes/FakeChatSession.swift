// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковая сессия чата для тестов `ActiveRoom` и `RoomService`.
///
/// Реализует `HostSessionManaging` (наследует `ChatSessionManaging`), поэтому подходит
/// как для клиентских, так и для хост-сессий. Все мутируемые поля защищены `NSLock` —
/// отсюда `@unchecked Sendable`.
final class FakeChatSession: HostSessionManaging, @unchecked Sendable {

    // MARK: - HostSessionManaging / ChatSessionManaging

    nonisolated let role: SessionRole
    nonisolated let events: AsyncStream<SessionEvent>
    nonisolated let sessionID: UUID
    nonisolated let invite: RoomInvite
    /// `PermanentPeerID`, который возвращают сообщения из `send(text:)`.
    nonisolated let senderID: UUID

    // MARK: - Внутреннее состояние (защищены NSLock)

    // NSLock обеспечивает взаимоисключение при доступе из параллельных тестов.
    private let lock = NSLock()
    private var continuation: AsyncStream<SessionEvent>.Continuation?
    private var _sentTexts: [String] = []
    /// Если задана — `send(text:)` бросает эту ошибку вместо успеха.
    var sendError: (any Error)?

    // MARK: - Наблюдаемые свойства для тестов

    var sentTexts: [String] { lock.withLock { _sentTexts } }

    // MARK: - Инициализация

    init(role: SessionRole = .client,
         sessionID: UUID = UUID(),
         senderID: UUID = UUID()) {
        self.role = role
        self.sessionID = sessionID
        self.senderID = senderID
        let roomKey = Data(repeating: 0xAB, count: 32)
        self.invite = RoomInvite(version: RoomInvite.currentVersion,
                                 serviceName: UUID().uuidString,
                                 roomKey: roomKey)
        var cont: AsyncStream<SessionEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // MARK: - Вспомогательные методы для тестов

    /// Отправляет событие в поток.
    func emit(_ event: SessionEvent) {
        lock.withLock { _ = continuation?.yield(event) }
    }

    /// Завершает поток событий (имитирует конец сессии).
    func finish() {
        lock.withLock { continuation?.finish(); continuation = nil }
    }

    // MARK: - ChatSessionManaging

    nonisolated func start() async {}

    nonisolated func send(text: String) async throws -> ChatMessage {
        let error: (any Error)? = lock.withLock {
            _sentTexts.append(text)
            return sendError
        }
        if let error { throw error }
        return ChatMessage(id: UUID(), text: text,
                           timestamp: Date().flooredToMilliseconds,
                           senderID: senderID)
    }

    nonisolated func end() async {
        lock.withLock { continuation?.finish(); continuation = nil }
    }
}

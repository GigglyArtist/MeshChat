// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Постоянное хранилище приложения. Все методы потокобезопасны и отдают только доменные значения.
protocol StorageManaging: Sendable {

    // MARK: Sessions

    /// Создаёт сессию с указанными параметрами и возвращает её.
    /// Идемпотентно: если сессия с таким `id` уже есть — возвращает её без изменений.
    @discardableResult
    nonisolated func createSession(id: UUID, role: SessionRole, createdAt: Date) async throws -> ChatSessionInfo

    /// Проставляет дату завершения сессии.
    /// Бросает `StorageError.sessionNotFound`, если сессия не существует.
    nonisolated func endSession(id: UUID, endedAt: Date) async throws

    /// Удаляет сессию и каскадно — все её сообщения. Peer остаются.
    /// Бросает `StorageError.sessionNotFound`, если сессия не существует.
    nonisolated func deleteSession(id: UUID) async throws

    /// Возвращает сессию по `id`, или `nil` если не найдена.
    nonisolated func session(id: UUID) async throws -> ChatSessionInfo?

    /// Возвращает все известные сессии, новые сверху (сортировка по `createdAt` убывая).
    nonisolated func allSessions() async throws -> [ChatSessionInfo]

    // MARK: Peers

    /// Fetch-or-create по `PermanentPeerID`: если собеседник есть — обновляет никнейм и `lastSeenAt`;
    /// если нет — создаёт. Возвращает актуальный профиль.
    @discardableResult
    nonisolated func upsertPeer(_ profile: PeerProfile, seenAt: Date) async throws -> PeerProfile

    /// Возвращает профиль собеседника по `id`, или `nil` если не найден.
    nonisolated func peer(id: UUID) async throws -> PeerProfile?

    /// Возвращает всех известных собеседников, недавних сверху (сортировка по `lastSeenAt` убывая).
    nonisolated func allPeers() async throws -> [PeerProfile]

    /// Привязывает существующего собеседника к сессии как участника. Идемпотентно.
    /// Бросает `sessionNotFound` / `peerNotFound`, если одна из сторон не существует.
    nonisolated func addParticipant(peerID: UUID, toSession sessionID: UUID) async throws

    /// Возвращает все сессии, в которых участвовал данный собеседник, новые сверху.
    /// Используется для отображения истории переписки с конкретным человеком (R14).
    nonisolated func sessions(withPeer peerID: UUID) async throws -> [ChatSessionInfo]

    // MARK: Messages

    /// Сохраняет сообщение в указанную сессию. Идемпотентно по `message.id`.
    /// Бросает `StorageError.sessionNotFound`, если сессия не существует.
    nonisolated func saveMessage(_ message: ChatMessage, inSession sessionID: UUID) async throws

    /// Возвращает сообщения сессии, отсортированные по `timestamp` возрастая.
    /// Бросает `StorageError.sessionNotFound`, если сессия не существует.
    nonisolated func messages(inSession sessionID: UUID) async throws -> [ChatMessage]
}

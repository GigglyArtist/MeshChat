// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Протокол доступа к истории переписки (§11).
///
/// Реализуется `HistoryService` в слое Application.
/// Все методы потокобезопасны и не содержат ссылок на Core Data.
protocol HistoryServicing: Sendable {

    /// Все известные собеседники; сначала с более свежей сессией, без сессий — в конце (по нику).
    nonisolated func peerSummaries() async throws -> [PeerSummary]

    /// Сессии с этим человеком, новые сверху (§10.4).
    nonisolated func sessions(withPeer peerID: UUID) async throws -> [ChatSessionInfo]

    /// Переписка сессии с сообщениями по возрастанию `timestamp`.
    /// Бросает `StorageError.sessionNotFound(sessionID)`, если сессия не найдена.
    nonisolated func transcript(sessionID: UUID) async throws -> SessionTranscript

    /// Удаляет сессию и её сообщения (Cascade); собеседники остаются (R13).
    /// Бросает `StorageError.sessionNotFound(id)`, если сессия не найдена.
    nonisolated func deleteSession(id: UUID) async throws
}

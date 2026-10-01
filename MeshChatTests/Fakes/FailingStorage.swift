// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Хранилище, которое бросает ошибку на всех записях.
///
/// Используется для проверки, что ошибки хранилища во время живого чата
/// не прерывают работу `ActiveRoom` (§11.1).
nonisolated struct FailingStorage: StorageManaging {

    private static let error = StorageError.saveFailed("injected failure")

    // MARK: Sessions

    nonisolated func createSession(id: UUID, role: SessionRole, createdAt: Date) async throws -> ChatSessionInfo {
        throw Self.error
    }

    nonisolated func endSession(id: UUID, endedAt: Date) async throws {
        throw Self.error
    }

    nonisolated func deleteSession(id: UUID) async throws {
        throw Self.error
    }

    nonisolated func session(id: UUID) async throws -> ChatSessionInfo? { nil }

    nonisolated func allSessions() async throws -> [ChatSessionInfo] { [] }

    // MARK: Peers

    nonisolated func upsertPeer(_ profile: PeerProfile, seenAt: Date) async throws -> PeerProfile {
        throw Self.error
    }

    nonisolated func peer(id: UUID) async throws -> PeerProfile? { nil }

    nonisolated func allPeers() async throws -> [PeerProfile] { [] }

    nonisolated func addParticipant(peerID: UUID, toSession sessionID: UUID) async throws {
        throw Self.error
    }

    nonisolated func sessions(withPeer peerID: UUID) async throws -> [ChatSessionInfo] { [] }

    // MARK: Messages

    nonisolated func saveMessage(_ message: ChatMessage, inSession sessionID: UUID) async throws {
        throw Self.error
    }

    nonisolated func messages(inSession sessionID: UUID) async throws -> [ChatMessage] { [] }
}

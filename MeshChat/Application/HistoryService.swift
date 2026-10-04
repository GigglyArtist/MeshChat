// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Тонкий слой над `StorageManaging`: собирает данные для экранов истории (§11).
///
/// Без своего состояния — только оборачивает запросы к хранилищу.
nonisolated struct HistoryService: HistoryServicing {

    private let storage: any StorageManaging

    nonisolated init(storage: any StorageManaging) {
        self.storage = storage
    }

    nonisolated func peerSummaries() async throws -> [PeerSummary] {
        let peers = try await storage.allPeers()
        var summaries: [PeerSummary] = []
        for peer in peers {
            let sessions = try await storage.sessions(withPeer: peer.id)
            summaries.append(PeerSummary(
                profile: peer,
                sessionCount: sessions.count,
                lastSessionAt: sessions.first?.createdAt  // sessions уже отсортированы новые сверху
            ))
        }
        return summaries.sorted { a, b in
            switch (a.lastSessionAt, b.lastSessionAt) {
            case (.some(let da), .some(let db)):
                return da > db
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return a.profile.nickname.localizedStandardCompare(b.profile.nickname) == .orderedAscending
            }
        }
    }

    nonisolated func sessions(withPeer peerID: UUID) async throws -> [ChatSessionInfo] {
        try await storage.sessions(withPeer: peerID)
    }

    nonisolated func transcript(sessionID: UUID) async throws -> SessionTranscript {
        guard let session = try await storage.session(id: sessionID) else {
            throw StorageError.sessionNotFound(sessionID)
        }
        let messages = try await storage.messages(inSession: sessionID)
        return SessionTranscript(session: session, messages: messages)
    }

    nonisolated func deleteSession(id: UUID) async throws {
        try await storage.deleteSession(id: id)
    }
}

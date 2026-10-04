// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Observation

/// ViewModel экрана сессий с одним собеседником (§12.1.2).
@Observable @MainActor final class PeerHistoryViewModel {

    private(set) var sessions: [ChatSessionInfo] = []
    private(set) var errorMessage: String?

    let peer: PeerProfile
    private let history: any HistoryServicing

    init(peer: PeerProfile, history: any HistoryServicing) {
        self.peer = peer
        self.history = history
    }

    func load() async {
        do {
            sessions = try await history.sessions(withPeer: peer.id)
            errorMessage = nil
        } catch {
            errorMessage = "Не удалось загрузить историю"
        }
    }

    func delete(sessionID: UUID) async {
        do {
            try await history.deleteSession(id: sessionID)
            await load()
        } catch {
            errorMessage = "Не удалось удалить переписку"
        }
    }
}

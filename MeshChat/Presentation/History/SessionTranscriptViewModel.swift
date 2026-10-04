// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Observation

/// ViewModel экрана переписки одной сессии (§12.1.2).
@Observable @MainActor final class SessionTranscriptViewModel {

    private(set) var rows: [ChatViewModel.Item] = []
    private(set) var title: String = ""
    private(set) var isEmpty: Bool = true
    private(set) var errorMessage: String?

    private let sessionID: UUID
    private let localPeerID: UUID
    private let history: any HistoryServicing

    init(sessionID: UUID, localPeerID: UUID, history: any HistoryServicing) {
        self.sessionID = sessionID
        self.localPeerID = localPeerID
        self.history = history
    }

    func load() async {
        do {
            let transcript = try await history.transcript(sessionID: sessionID)
            title = HistoryFormatting.sessionTitle(transcript.session)

            var names: [UUID: String] = [:]
            for p in transcript.session.participants {
                names[p.id] = p.nickname
            }

            rows = transcript.messages.map { msg in
                let isOutgoing = msg.senderID == localPeerID
                let name: String
                if isOutgoing {
                    name = "Вы"
                } else {
                    name = names[msg.senderID] ?? "Неизвестный"
                }
                return .message(msg, isOutgoing: isOutgoing, authorName: name)
            }
            isEmpty = rows.isEmpty
            errorMessage = nil
        } catch {
            errorMessage = "Переписка не найдена"
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

@Suite("HistoryFormattingTests")
struct HistoryFormattingTests {

    // MARK: peerSubtitle

    @Test("peerSubtitle with 0 sessions returns 'Нет сохранённых чатов'")
    func peerSubtitleNoSessions() {
        let peer = PeerProfile(id: UUID(), nickname: "Alice")
        let summary = PeerSummary(profile: peer, sessionCount: 0, lastSessionAt: nil)
        #expect(HistoryFormatting.peerSubtitle(summary) == "Нет сохранённых чатов")
    }

    @Test("peerSubtitle with 3 sessions starts with '3 чата'")
    func peerSubtitleThreeSessions() {
        let peer = PeerProfile(id: UUID(), nickname: "Alice")
        let date = Date(timeIntervalSince1970: 0)
        let summary = PeerSummary(profile: peer, sessionCount: 3, lastSessionAt: date)
        #expect(HistoryFormatting.peerSubtitle(summary).hasPrefix("3 чата"))
    }

    // MARK: sessionSubtitle

    @Test("sessionSubtitle for host lists participants alphabetically")
    func sessionSubtitleHostWithParticipants() {
        let vova = PeerProfile(id: UUID(), nickname: "Вова")
        let anya = PeerProfile(id: UUID(), nickname: "Аня")
        let session = ChatSessionInfo(
            id: UUID(), createdAt: Date(), endedAt: nil, role: .host,
            participants: [vova, anya]  // намеренно не по порядку
        )
        let subtitle = HistoryFormatting.sessionSubtitle(session)
        #expect(subtitle.hasPrefix("Вы были хостом"))
        // Аня идёт раньше Вовы
        #expect(subtitle.contains("Аня, Вова"))
    }

    @Test("sessionSubtitle for client without participants")
    func sessionSubtitleClientNoParticipants() {
        let session = ChatSessionInfo(
            id: UUID(), createdAt: Date(), endedAt: nil, role: .client, participants: []
        )
        #expect(HistoryFormatting.sessionSubtitle(session) == "Вы были участником")
    }
}

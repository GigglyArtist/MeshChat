// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

@MainActor
@Suite("SessionTranscriptViewModelTests", .serialized)
struct SessionTranscriptViewModelTests {

    let localPeerID = UUID()

    // MARK: - Вспомогательные методы

    func makeSession(id: UUID, participants: [PeerProfile] = []) -> ChatSessionInfo {
        ChatSessionInfo(id: id, createdAt: Date(), endedAt: nil, role: .host, participants: participants)
    }

    // MARK: Тест 1: «Вы» для своих, ник участника для чужих

    @Test("own messages are outgoing with name 'Вы', peer messages have nickname")
    func outgoingAndIncoming() async {
        let peerID = UUID()
        let peer = PeerProfile(id: peerID, nickname: "Alice")
        let sessionID = UUID()
        let session = makeSession(id: sessionID, participants: [peer])

        let t1 = Date(timeIntervalSince1970: 100).flooredToMilliseconds
        let t2 = Date(timeIntervalSince1970: 200).flooredToMilliseconds
        let msg1 = ChatMessage(id: UUID(), text: "hi", timestamp: t1, senderID: localPeerID)
        let msg2 = ChatMessage(id: UUID(), text: "hello", timestamp: t2, senderID: peerID)

        let transcript = SessionTranscript(session: session, messages: [msg1, msg2])
        let service = FakeHistoryService(transcript: transcript)
        let vm = SessionTranscriptViewModel(
            sessionID: sessionID, localPeerID: localPeerID, history: service
        )

        await vm.load()

        #expect(vm.errorMessage == nil)
        #expect(vm.rows.count == 2)

        if case .message(_, let isOut, let name) = vm.rows[0] {
            #expect(isOut == true)
            #expect(name == "Вы")
        } else {
            Issue.record("Expected .message for rows[0]")
        }

        if case .message(_, let isOut, let name) = vm.rows[1] {
            #expect(isOut == false)
            #expect(name == "Alice")
        } else {
            Issue.record("Expected .message for rows[1]")
        }
    }

    // MARK: Тест 2: «Неизвестный» для ID не из участников

    @Test("sender not in participants shown as 'Неизвестный'")
    func unknownSender() async {
        let sessionID = UUID()
        let session = makeSession(id: sessionID)
        let unknownID = UUID()
        let msg = ChatMessage(
            id: UUID(), text: "???",
            timestamp: Date().flooredToMilliseconds, senderID: unknownID
        )
        let transcript = SessionTranscript(session: session, messages: [msg])
        let service = FakeHistoryService(transcript: transcript)
        let vm = SessionTranscriptViewModel(
            sessionID: sessionID, localPeerID: localPeerID, history: service
        )

        await vm.load()

        if case .message(_, _, let name) = vm.rows.first {
            #expect(name == "Неизвестный")
        } else {
            Issue.record("Expected .message")
        }
    }

    // MARK: Тест 3: порядок по возрастанию времени

    @Test("messages appear in ascending timestamp order")
    func messagesAscendingOrder() async {
        let sessionID = UUID()
        let session = makeSession(id: sessionID)
        let t1 = Date(timeIntervalSince1970: 100).flooredToMilliseconds
        let t2 = Date(timeIntervalSince1970: 200).flooredToMilliseconds
        let t3 = Date(timeIntervalSince1970: 300).flooredToMilliseconds
        let msg1 = ChatMessage(id: UUID(), text: "a", timestamp: t1, senderID: localPeerID)
        let msg2 = ChatMessage(id: UUID(), text: "b", timestamp: t2, senderID: localPeerID)
        let msg3 = ChatMessage(id: UUID(), text: "c", timestamp: t3, senderID: localPeerID)

        // SessionTranscript уже хранит по возрастанию (§11)
        let transcript = SessionTranscript(session: session, messages: [msg1, msg2, msg3])
        let service = FakeHistoryService(transcript: transcript)
        let vm = SessionTranscriptViewModel(
            sessionID: sessionID, localPeerID: localPeerID, history: service
        )

        await vm.load()

        let texts = vm.rows.compactMap { item -> String? in
            if case .message(let m, _, _) = item { return m.text }
            return nil
        }
        #expect(texts == ["a", "b", "c"])
    }

    // MARK: Тест 4: неизвестная сессия → «Переписка не найдена»

    @Test("unknown session sets errorMessage 'Переписка не найдена'")
    func unknownSessionSetsError() async {
        let unknownID = UUID()
        let service = FakeHistoryService(transcriptError: StorageError.sessionNotFound(unknownID))
        let vm = SessionTranscriptViewModel(
            sessionID: unknownID, localPeerID: localPeerID, history: service
        )

        await vm.load()

        #expect(vm.errorMessage == "Переписка не найдена")
        #expect(vm.rows.isEmpty)
    }
}

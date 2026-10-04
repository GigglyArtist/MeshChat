// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

@MainActor
@Suite("PeerHistoryViewModelTests", .serialized)
struct PeerHistoryViewModelTests {

    let peer = PeerProfile(id: UUID(), nickname: "Alice")

    @Test("load populates sessions")
    func loadPopulatesSessions() async {
        let session = ChatSessionInfo(
            id: UUID(), createdAt: Date(), endedAt: nil, role: .host, participants: []
        )
        let service = FakeHistoryService(sessions: [session])
        let vm = PeerHistoryViewModel(peer: peer, history: service)

        await vm.load()

        #expect(vm.sessions.count == 1)
        #expect(vm.errorMessage == nil)
    }

    @Test("delete calls deleteSession and reloads")
    func deleteCallsDeleteAndReloads() async {
        let sessionID = UUID()
        let session = ChatSessionInfo(
            id: sessionID, createdAt: Date(), endedAt: nil, role: .host, participants: []
        )
        let service = FakeHistoryService(sessions: [session])
        let vm = PeerHistoryViewModel(peer: peer, history: service)
        await vm.load()
        #expect(vm.sessions.count == 1)

        // После удаления сервис возвращает пустой список
        service.sessions = []
        await vm.delete(sessionID: sessionID)

        #expect(service.deletedSessionIDs.contains(sessionID))
        #expect(vm.sessions.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test("delete error sets errorMessage")
    func deleteErrorSetsMessage() async {
        let sessionID = UUID()
        let service = FakeHistoryService()
        service.deleteError = StorageError.sessionNotFound(sessionID)
        let vm = PeerHistoryViewModel(peer: peer, history: service)

        await vm.delete(sessionID: sessionID)

        #expect(vm.errorMessage == "Не удалось удалить переписку")
    }
}

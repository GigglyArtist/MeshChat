// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

@MainActor
@Suite("HistoryViewModelTests", .serialized)
struct HistoryViewModelTests {

    @Test("loaded state contains peer summaries")
    func loadedState() async {
        let peer = PeerProfile(id: UUID(), nickname: "Alice")
        let summary = PeerSummary(profile: peer, sessionCount: 1, lastSessionAt: Date())
        let service = FakeHistoryService(peers: [summary])
        let vm = HistoryViewModel(history: service)

        await vm.load()

        if case .loaded(let summaries) = vm.state {
            #expect(summaries.count == 1)
        } else {
            Issue.record("Expected .loaded, got \(vm.state)")
        }
    }

    @Test("empty summaries results in loaded state with empty array")
    func emptyState() async {
        let service = FakeHistoryService()
        let vm = HistoryViewModel(history: service)

        await vm.load()

        if case .loaded(let summaries) = vm.state {
            #expect(summaries.isEmpty)
        } else {
            Issue.record("Expected .loaded([]), got \(vm.state)")
        }
    }

    @Test("load error results in failed state with correct message")
    func errorState() async {
        let service = FakeHistoryService(peersError: StorageError.saveFailed("test"))
        let vm = HistoryViewModel(history: service)

        await vm.load()

        if case .failed(let message) = vm.state {
            #expect(message == "Не удалось загрузить историю")
        } else {
            Issue.record("Expected .failed, got \(vm.state)")
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Observation

/// ViewModel экрана списка собеседников (§12.1, §12.2).
@Observable @MainActor final class HistoryViewModel {

    enum State {
        case loading
        case loaded([PeerSummary])
        case failed(String)
    }

    private(set) var state: State = .loading

    private let history: any HistoryServicing

    init(history: any HistoryServicing) {
        self.history = history
    }

    func load() async {
        state = .loading
        do {
            let summaries = try await history.peerSummaries()
            state = .loaded(summaries)
        } catch {
            state = .failed("Не удалось загрузить историю")
        }
    }
}

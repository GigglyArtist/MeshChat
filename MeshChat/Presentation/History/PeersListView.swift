// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Экран списка собеседников (§12.1.2).
struct PeersListView: View {

    @State private var viewModel: HistoryViewModel
    private let onPeer: (PeerProfile) -> Void

    init(history: any HistoryServicing, onPeer: @escaping (PeerProfile) -> Void) {
        _viewModel = State(wrappedValue: HistoryViewModel(history: history))
        self.onPeer = onPeer
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let summaries):
                if summaries.isEmpty {
                    ContentUnavailableView(
                        "Нет собеседников",
                        systemImage: "person.2",
                        description: Text("Здесь появятся люди, с которыми вы переписывались")
                    )
                } else {
                    List(summaries) { summary in
                        Button(action: { onPeer(summary.profile) }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.profile.nickname)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(HistoryFormatting.peerSubtitle(summary))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .refreshable { await viewModel.load() }
                }
            case .failed(let message):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .navigationTitle("История")
        .onAppear { Task { await viewModel.load() } }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PeersListView(history: PreviewHistoryService()) { _ in }
    }
}
#endif

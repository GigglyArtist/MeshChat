// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Экран переписки одной сессии — только чтение (§12.1.2).
struct SessionTranscriptView: View {

    @State private var viewModel: SessionTranscriptViewModel

    init(sessionID: UUID, localPeerID: UUID, history: any HistoryServicing) {
        _viewModel = State(wrappedValue: SessionTranscriptViewModel(
            sessionID: sessionID,
            localPeerID: localPeerID,
            history: history
        ))
    }

    var body: some View {
        Group {
            if let message = viewModel.errorMessage {
                ContentUnavailableView(
                    "Переписка не найдена",
                    systemImage: "exclamationmark.bubble",
                    description: Text(message)
                )
            } else if viewModel.isEmpty {
                ContentUnavailableView(
                    "Сообщений нет",
                    systemImage: "bubble.left"
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        Text("Только чтение")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)

                        LazyVStack(spacing: 4) {
                            ForEach(viewModel.rows) { item in
                                ChatRow(item: item)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await viewModel.load() } }
    }
}

#if DEBUG
#Preview {
    let sessionID = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
    let localPeerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    NavigationStack {
        SessionTranscriptView(
            sessionID: sessionID,
            localPeerID: localPeerID,
            history: PreviewHistoryService()
        )
    }
}
#endif

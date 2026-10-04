// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Экран списка сессий с одним собеседником (§12.1.2).
struct PeerHistoryView: View {

    @State private var viewModel: PeerHistoryViewModel
    @State private var sessionToDelete: UUID?
    private let onSession: (UUID) -> Void

    init(peer: PeerProfile, history: any HistoryServicing, onSession: @escaping (UUID) -> Void) {
        _viewModel = State(wrappedValue: PeerHistoryViewModel(peer: peer, history: history))
        self.onSession = onSession
    }

    var body: some View {
        Group {
            if let message = viewModel.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .padding()
            } else if viewModel.sessions.isEmpty {
                ContentUnavailableView(
                    "Чатов не осталось",
                    systemImage: "bubble.left.and.bubble.right.fill"
                )
            } else {
                List {
                    ForEach(viewModel.sessions) { session in
                        Button(action: { onSession(session.id) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(HistoryFormatting.sessionTitle(session))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(HistoryFormatting.sessionSubtitle(session))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Удалить", role: .destructive) {
                                sessionToDelete = session.id
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.peer.nickname)
        .onAppear { Task { await viewModel.load() } }
        .confirmationDialog(
            "Удалить переписку? Она удалится только на этом устройстве",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = sessionToDelete {
                Button("Удалить", role: .destructive) {
                    let deleteID = id
                    sessionToDelete = nil
                    Task { await viewModel.delete(sessionID: deleteID) }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PeerHistoryView(
            peer: PeerProfile(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
                              nickname: "Аня"),
            history: PreviewHistoryService()
        ) { _ in }
    }
}
#endif

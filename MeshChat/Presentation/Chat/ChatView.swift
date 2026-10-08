// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Экран активной комнаты: лента сообщений, ввод, баннер состояния (§12.1.1).
struct ChatView: View {

    @State private var viewModel: ChatViewModel
    @State private var showLeaveConfirmation = false
    @State private var showQRSheet = false
    @Environment(\.scenePhase) private var scenePhase

    private let onLeave: () -> Void
    private let onRejoined: (ChatRoute) -> Void

    init(room: any ActiveRoomHandling,
         localNickname: String,
         rejoinInvite: RoomInvite? = nil,
         rooms: (any RoomServicing)? = nil,
         onLeave: @escaping () -> Void,
         onRejoined: @escaping (ChatRoute) -> Void = { _ in }) {
        _viewModel = State(wrappedValue: ChatViewModel(
            room: room, localNickname: localNickname,
            rejoinInvite: rejoinInvite, rooms: rooms))
        self.onLeave = onLeave
        self.onRejoined = onRejoined
    }

    var body: some View {
        VStack(spacing: 0) {
            SessionBanner(state: viewModel.sessionState)

            if let err = viewModel.sendError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }

            if viewModel.isRejoining {
                ProgressView()
                    .padding(.vertical, 4)
            } else if viewModel.canRejoin {
                Button("Подключиться снова") {
                    Task { await viewModel.rejoin() }
                }
                .buttonStyle(.borderedProminent)
                .padding(.vertical, 4)
            }

            messageList

            if viewModel.isInputVisible {
                ChatInputBar(
                    text: $viewModel.draft,
                    canSend: viewModel.canSend,
                    onSend: { await viewModel.send() }
                )
            }
        }
        .navigationTitle(viewModel.participantCountTitle)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await viewModel.appDidBecomeActive() } }
        }
        .onChange(of: viewModel.sessionState) { _, newState in
            if case .ended(.leftByUser) = newState { viewModel.exitToHome(); onLeave() }
        }
        .onChange(of: viewModel.rejoinedRoute) { _, route in
            if let route { onRejoined(route) }
        }
        .confirmationDialog(
            viewModel.role == .host ? "Завершить комнату?" : "Выйти из комнаты?",
            isPresented: $showLeaveConfirmation
        ) {
            Button(viewModel.role == .host ? "Завершить" : "Выйти", role: .destructive) {
                Task { await viewModel.leave() }
            }
        }
        .sheet(isPresented: $showQRSheet) {
            qrSheet
        }
    }

    // MARK: - Подвиды

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.items) { item in
                        ChatRow(item: item)
                            .id(item.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.items.count) {
                if let last = viewModel.items.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if case .ended(let reason) = viewModel.sessionState, reason != .leftByUser {
                Button("Закрыть") { viewModel.exitToHome(); onLeave() }
            } else if !viewModel.isEnded {
                Button(viewModel.role == .host ? "Завершить" : "Выйти") {
                    showLeaveConfirmation = true
                }
            }
        }
        if viewModel.role == .host, viewModel.invite != nil {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showQRSheet = true
                } label: {
                    Image(systemName: "qrcode")
                }
            }
        }
    }

    @ViewBuilder
    private var qrSheet: some View {
        if let payload = viewModel.qrPayload {
            NavigationStack {
                RoomQRCodeView(qrPayload: payload)
                    .navigationTitle("QR-код комнаты")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Готово") { showQRSheet = false }
                        }
                    }
            }
        } else {
            Text("Не удалось построить QR-код")
        }
    }
}

// MARK: - Computed helper

private extension ChatViewModel {
    var isEnded: Bool {
        if case .ended = sessionState { return true }
        return false
    }
}

#if DEBUG
#Preview("Host chat") {
    let env = AppEnvironment.preview(hasNickname: true)
    let room = PreviewActiveRoom(role: .host)
    return NavigationStack {
        ChatView(
            room: room,
            localNickname: env.identity.nickname() ?? "Preview",
            onLeave: {}
        )
    }
}

#Preview("Client chat") {
    let env = AppEnvironment.preview(hasNickname: true)
    let room = PreviewActiveRoom(role: .client)
    return NavigationStack {
        ChatView(
            room: room,
            localNickname: env.identity.nickname() ?? "Preview",
            onLeave: {}
        )
    }
}
#endif

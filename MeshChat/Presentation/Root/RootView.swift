// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Корневой контейнер: выбирает между онбордингом и главным экраном (§12.1).
struct RootView: View {

    @State private var viewModel: RootViewModel
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = State(wrappedValue: RootViewModel(identity: environment.identity))
    }

    var body: some View {
        switch viewModel.destination {
        case .onboarding:
            OnboardingView(identity: environment.identity) {
                viewModel.didCompleteOnboarding()
            }
        case .home:
            homeNavigationStack
        }
    }

    private var localNickname: String {
        environment.identity.nickname() ?? ""
    }

    private var homeNavigationStack: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            HomeView(
                nickname: environment.identity.nickname() ?? "",
                onCreateRoom: { viewModel.navigate(to: .createRoom) },
                onJoinRoom: { viewModel.navigate(to: .joinRoom) },
                onHistory: { viewModel.navigate(to: .history) }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .createRoom:
                    CreateRoomView(rooms: environment.rooms) { room in
                        viewModel.navigateToChat(route: ChatRoute(room: room))
                    }
                case .joinRoom:
                    JoinRoomView(rooms: environment.rooms) { route in
                        viewModel.navigateToChat(route: route)
                    }
                case .chat(let chatRoute):
                    ChatView(
                        room: chatRoute.room,
                        localNickname: localNickname,
                        rejoinInvite: chatRoute.rejoinInvite,
                        rooms: environment.rooms,
                        onLeave: { viewModel.navigationPath.removeAll() },
                        onRejoined: { route in viewModel.navigationPath = [.chat(route)] }
                    )
                case .history:
                    PeersListView(history: environment.history) { peer in
                        viewModel.navigate(to: .peerHistory(peer))
                    }
                case .peerHistory(let peer):
                    PeerHistoryView(peer: peer, history: environment.history) { sessionID in
                        viewModel.navigate(to: .transcript(sessionID: sessionID))
                    }
                case .transcript(let sessionID):
                    SessionTranscriptView(
                        sessionID: sessionID,
                        localPeerID: environment.localPeerID,
                        history: environment.history
                    )
                }
            }
        }
    }
}

#if DEBUG
#Preview("Home") {
    RootView(environment: AppEnvironment.preview(hasNickname: true))
}

#Preview("Onboarding") {
    RootView(environment: AppEnvironment.preview(hasNickname: false))
}
#endif

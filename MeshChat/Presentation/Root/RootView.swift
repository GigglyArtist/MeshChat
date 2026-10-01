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
                onJoinRoom: { viewModel.navigate(to: .joinRoom) }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .createRoom:
                    CreateRoomView(rooms: environment.rooms) { room in
                        viewModel.navigateToChat(room: room)
                    }
                case .joinRoom:
                    JoinRoomView(rooms: environment.rooms) { room in
                        viewModel.navigateToChat(room: room)
                    }
                case .chat(let chatRoute):
                    ChatView(
                        room: chatRoute.room,
                        localNickname: localNickname,
                        onLeave: { viewModel.navigationPath.removeAll() }
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

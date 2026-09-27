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
            HomeView()
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

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Observation

/// Управляет навигацией верхнего уровня: онбординг или главный экран (§12.1).
@Observable @MainActor final class RootViewModel {

    enum Destination {
        case onboarding
        case home
    }

    private(set) var destination: Destination
    var navigationPath: [Route] = []

    init(identity: any IdentityProviding) {
        destination = identity.nickname() == nil ? .onboarding : .home
    }

    /// Вызывается после завершения онбординга; переключает на главный экран.
    func didCompleteOnboarding() {
        destination = .home
    }

    func navigate(to route: Route) {
        navigationPath.append(route)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
@testable import MeshChat

@Suite("RootViewModel", .serialized)
@MainActor
struct RootViewModelTests {

    @Test("Без никнейма — destination == .onboarding")
    func destinationOnboarding() {
        let identity = FakeIdentityProvider(nickname: nil)
        let vm = RootViewModel(identity: identity)
        #expect(vm.destination == .onboarding)
    }

    @Test("С никнеймом — destination == .home")
    func destinationHome() {
        let identity = FakeIdentityProvider(nickname: "Alice")
        let vm = RootViewModel(identity: identity)
        #expect(vm.destination == .home)
    }

    @Test("didCompleteOnboarding переключает destination на .home")
    func didCompleteOnboarding() {
        let identity = FakeIdentityProvider(nickname: nil)
        let vm = RootViewModel(identity: identity)
        #expect(vm.destination == .onboarding)
        vm.didCompleteOnboarding()
        #expect(vm.destination == .home)
    }
}

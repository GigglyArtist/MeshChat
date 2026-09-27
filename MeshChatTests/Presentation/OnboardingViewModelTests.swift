// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
@testable import MeshChat

@Suite("OnboardingViewModel", .serialized)
@MainActor
struct OnboardingViewModelTests {

    private func makeViewModel(
        identity: FakeIdentityProvider = FakeIdentityProvider(),
        onComplete: @escaping () -> Void = {}
    ) -> OnboardingViewModel {
        OnboardingViewModel(identity: identity, onComplete: onComplete)
    }

    @Test("Пустой ввод — canContinue == false")
    func canContinueFalseInitially() {
        #expect(!makeViewModel().canContinue)
    }

    @Test("Валидный ник — canContinue == true")
    func canContinueTrueWithValidName() {
        let vm = makeViewModel()
        vm.nicknameInput = "Alice"
        #expect(vm.canContinue)
    }

    @Test("Строка из пробелов — canContinue == false")
    func canContinueFalseWithWhitespace() {
        let vm = makeViewModel()
        vm.nicknameInput = "   "
        #expect(!vm.canContinue)
    }

    @Test("continueAction с валидным ником сохраняет нормализованное имя в identity")
    func continueActionSavesNickname() {
        let identity = FakeIdentityProvider()
        let vm = makeViewModel(identity: identity)
        vm.nicknameInput = "  Bob  "
        vm.continueAction()
        #expect(identity.storedNickname == "Bob")
    }

    @Test("continueAction вызывает onComplete после успешного сохранения ника")
    func continueActionCallsOnComplete() {
        let identity = FakeIdentityProvider()
        // Используем класс-обёртку, чтобы не замыкать изменяемую переменную в @Sendable-контекст
        final class Counter { var value = 0 }
        let counter = Counter()
        let vm = makeViewModel(identity: identity, onComplete: { counter.value += 1 })
        vm.nicknameInput = "Alice"
        vm.continueAction()
        #expect(counter.value == 1)
    }

    @Test("continueAction с пустым вводом не вызывает identity.setNickname")
    func continueActionSkipsOnEmptyInput() {
        let identity = FakeIdentityProvider()
        let vm = makeViewModel(identity: identity)
        vm.continueAction()
        #expect(identity.setNicknameCalls.isEmpty)
    }

    @Test("continueAction при ошибке identity.setNickname устанавливает errorMessage")
    func continueActionSetsErrorMessage() {
        let identity = FakeIdentityProvider()
        identity.nicknameToThrow = IdentityError.keychain(status: -25300)
        let vm = makeViewModel(identity: identity)
        vm.nicknameInput = "Alice"
        vm.continueAction()
        #expect(vm.errorMessage != nil)
    }
}

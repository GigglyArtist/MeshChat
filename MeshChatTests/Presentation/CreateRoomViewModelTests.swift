// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

@MainActor
@Suite("CreateRoomViewModel", .serialized)
struct CreateRoomViewModelTests {

    func makeViewModel(
        createError: RoomError? = nil
    ) -> CreateRoomViewModel {
        CreateRoomViewModel(rooms: FakeRoomService(createError: createError))
    }

    // MARK: 1. canCreate

    @Test("Пустой пароль — canCreate == false")
    func canCreateFalseInitially() {
        #expect(!makeViewModel().canCreate)
    }

    @Test("Пароль меньше 4 символов — canCreate == false")
    func canCreateFalseShortPassword() {
        let vm = makeViewModel()
        vm.passwordInput = "abc"
        #expect(!vm.canCreate)
    }

    @Test("Пароль из одних пробелов — canCreate == false")
    func canCreateFalseAllSpaces() {
        let vm = makeViewModel()
        vm.passwordInput = "    "
        #expect(!vm.canCreate)
    }

    @Test("Валидный пароль — canCreate == true")
    func canCreateTrueWithValidPassword() {
        let vm = makeViewModel()
        vm.passwordInput = "secret123"
        #expect(vm.canCreate)
    }

    // MARK: 2. createRoom success

    @Test("createRoom с валидным паролем — createdRoom не nil")
    func createRoomSuccess() async throws {
        let vm = makeViewModel()
        vm.passwordInput = "secret123"
        await vm.createRoom()
        #expect(vm.createdRoom != nil)
    }

    @Test("createRoom очищает пароль")
    func createRoomClearsPassword() async {
        let vm = makeViewModel()
        vm.passwordInput = "secret123"
        await vm.createRoom()
        #expect(vm.passwordInput.isEmpty)
    }

    @Test("createRoom с пустым паролем ничего не делает")
    func createRoomIgnoresEmptyPassword() async {
        let vm = makeViewModel()
        await vm.createRoom()
        if case .editing = vm.state { } else {
            Issue.record("Expected .editing, got \(vm.state)")
        }
        #expect(vm.createdRoom == nil)
    }

    // MARK: 3. createRoom failure

    @Test("createRoom с nicknameMissing переходит в .failed")
    func createRoomNicknameMissingFails() async {
        let vm = makeViewModel(createError: .nicknameMissing)
        vm.passwordInput = "secret123"
        await vm.createRoom()
        if case .failed = vm.state { } else {
            Issue.record("Expected .failed, got \(vm.state)")
        }
        #expect(vm.createdRoom == nil)
    }
}

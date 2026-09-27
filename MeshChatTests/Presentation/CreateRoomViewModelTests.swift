// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

@Suite("CreateRoomViewModel", .serialized)
@MainActor
struct CreateRoomViewModelTests {

    private func makeViewModel(peerID: UUID = UUID()) -> CreateRoomViewModel {
        CreateRoomViewModel(secrets: RoomCredentialsFactory(), peerID: peerID)
    }

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

    @Test("createRoom с валидным паролем переходит в .ready")
    func createRoomTransitionsToReady() {
        let vm = makeViewModel()
        vm.passwordInput = "secret123"
        vm.createRoom()
        if case .ready = vm.state {
            // ok
        } else {
            Issue.record("Expected .ready, got \(vm.state)")
        }
    }

    @Test("createRoom очищает пароль")
    func createRoomClearsPassword() {
        let vm = makeViewModel()
        vm.passwordInput = "secret123"
        vm.createRoom()
        #expect(vm.passwordInput.isEmpty)
    }

    @Test("createRoom с пустым паролем не меняет состояние")
    func createRoomIgnoresEmptyPassword() {
        let vm = makeViewModel()
        vm.createRoom()
        if case .editing = vm.state {
            // ok
        } else {
            Issue.record("Expected .editing, got \(vm.state)")
        }
    }

    @Test("serviceName в приглашении совпадает с peerID")
    func serviceNameMatchesPeerID() {
        let peerID = UUID()
        let vm = makeViewModel(peerID: peerID)
        vm.passwordInput = "secret123"
        vm.createRoom()
        guard case .ready(let invite) = vm.state else {
            Issue.record("Expected .ready")
            return
        }
        #expect(invite.serviceName == peerID.uuidString)
    }
}

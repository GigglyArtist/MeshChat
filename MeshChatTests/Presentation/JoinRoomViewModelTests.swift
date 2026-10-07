// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

private let goldenRoomKey = Data(hex: "daaa69f872987f5f5d97fe64b7ab3ebabd3f6865f149b8db41413404d0639798")!
private let goldenServiceName = "6B1F2C8E-3D4A-4F5B-9C7D-8E9F0A1B2C3D"

@MainActor
@Suite("JoinRoomViewModel", .serialized)
struct JoinRoomViewModelTests {

    private func makeViewModel(
        cameraGranted: Bool = true,
        joinError: RoomError? = nil
    ) -> JoinRoomViewModel {
        let permission: CameraPermission = cameraGranted ? .granted : .denied
        return JoinRoomViewModel(
            rooms: FakeRoomService(joinError: joinError),
            checkCamera: { permission },
            requestCamera: { permission }
        )
    }

    private func validPayload() -> String {
        let invite = RoomInvite(version: 1, serviceName: goldenServiceName, roomKey: goldenRoomKey)
        return (try? invite.qrPayload()) ?? ""
    }

    // MARK: 1. Начальное состояние

    @Test("Начальное состояние — .checkingCamera")
    func initialStateIsCheckingCamera() {
        let vm = makeViewModel()
        if case .checkingCamera = vm.state { } else {
            Issue.record("Expected .checkingCamera, got \(vm.state)")
        }
    }

    // MARK: 2. handleScan

    @Test("handleScan с валидным QR переходит в .joining")
    func handleScanValidPayloadTransitionsToJoining() async {
        let vm = makeViewModel()
        await vm.prepare()
        vm.handleScan(validPayload())
        if case .joining = vm.state { } else {
            Issue.record("Expected .joining, got \(vm.state)")
        }
    }

    @Test("handleScan с мусором — состояние не меняется")
    func handleScanGarbageStaysScanning() async {
        let vm = makeViewModel()
        await vm.prepare()
        vm.handleScan("not-a-qr-code")
        if case .scanning = vm.state { } else {
            Issue.record("Expected .scanning, got \(vm.state)")
        }
    }

    @Test("handleScan с неподдерживаемой версией → .failed")
    func handleScanUnsupportedVersionFails() async throws {
        let vm = makeViewModel()
        await vm.prepare()
        let invite = RoomInvite(version: 99, serviceName: goldenServiceName, roomKey: goldenRoomKey)
        let payload = try invite.qrPayload()
        vm.handleScan(payload)
        if case .failed = vm.state { } else {
            Issue.record("Expected .failed, got \(vm.state)")
        }
    }

    @Test("handleScan игнорируется вне состояния .scanning")
    func handleScanIgnoredWhenNotScanning() {
        let vm = makeViewModel()
        vm.handleScan(validPayload())
        if case .checkingCamera = vm.state { } else {
            Issue.record("Expected .checkingCamera, got \(vm.state)")
        }
    }

    // MARK: 3. Асинхронный join

    @Test("handleScan с валидным QR — joinedRoom не nil после join")
    func handleScanSuccessfullyJoins() async throws {
        let vm = makeViewModel()
        await vm.prepare()
        vm.handleScan(validPayload())
        // Ждём завершения Task { await join(invite:) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.joinedRoom != nil)
    }

    @Test("handleScan при ошибке join → .failed")
    func handleScanJoinErrorFails() async throws {
        let vm = makeViewModel(joinError: .nicknameMissing)
        await vm.prepare()
        vm.handleScan(validPayload())
        try await Task.sleep(for: .milliseconds(100))
        if case .failed = vm.state { } else {
            Issue.record("Expected .failed, got \(vm.state)")
        }
        #expect(vm.joinedRoom == nil)
    }

    // MARK: 4. joinedRoute содержит то же приглашение, что было отсканировано

    @Test("after successful join, joinedRoute carries the scanned invite")
    func joinedRouteContainsSameInvite() async throws {
        let invite = RoomInvite(version: 1, serviceName: goldenServiceName, roomKey: goldenRoomKey)
        let payload = try invite.qrPayload()
        let vm = makeViewModel()
        await vm.prepare()
        vm.handleScan(payload)
        try await Task.sleep(for: .milliseconds(100))

        #expect(vm.joinedRoute != nil)
        #expect(vm.joinedRoute?.rejoinInvite == invite)
    }
}

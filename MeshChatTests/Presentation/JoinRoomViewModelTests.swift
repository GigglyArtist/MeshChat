// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

private let goldenRoomKey = Data(hex: "daaa69f872987f5f5d97fe64b7ab3ebabd3f6865f149b8db41413404d0639798")!
private let goldenServiceName = "6B1F2C8E-3D4A-4F5B-9C7D-8E9F0A1B2C3D"

@Suite("JoinRoomViewModel", .serialized)
@MainActor
struct JoinRoomViewModelTests {

    private func makeViewModel() -> JoinRoomViewModel {
        JoinRoomViewModel(secrets: RoomCredentialsFactory())
    }

    private func validPayload() -> String {
        let invite = RoomInvite(version: 1, serviceName: goldenServiceName, roomKey: goldenRoomKey)
        return (try? invite.qrPayload()) ?? ""
    }

    @Test("Начальное состояние — .checkingCamera")
    func initialStateIsCheckingCamera() {
        let vm = makeViewModel()
        if case .checkingCamera = vm.state { } else {
            Issue.record("Expected .checkingCamera, got \(vm.state)")
        }
    }

    @Test("handleScan с валидным QR → .found")
    func handleScanValidPayloadTransitionsToFound() {
        let vm = makeViewModel()
        vm.forceSetStateForTesting(.scanning)
        vm.handleScan(validPayload())
        if case .found = vm.state { } else {
            Issue.record("Expected .found, got \(vm.state)")
        }
    }

    @Test("handleScan с мусором — состояние не меняется")
    func handleScanGarbageStaysScanning() {
        let vm = makeViewModel()
        vm.forceSetStateForTesting(.scanning)
        vm.handleScan("not-a-qr-code")
        if case .scanning = vm.state { } else {
            Issue.record("Expected .scanning, got \(vm.state)")
        }
    }

    @Test("handleScan с неподдерживаемой версией → .failed")
    func handleScanUnsupportedVersionFails() throws {
        let vm = makeViewModel()
        vm.forceSetStateForTesting(.scanning)
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
        // Начальное состояние — checkingCamera, не scanning
        vm.handleScan(validPayload())
        if case .checkingCamera = vm.state { } else {
            Issue.record("Expected .checkingCamera, got \(vm.state)")
        }
    }
}


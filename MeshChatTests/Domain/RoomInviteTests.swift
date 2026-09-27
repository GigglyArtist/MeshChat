// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

// §6.4 контрольный пример: roomKey для "correct horse" + serviceName из примера
private let goldenRoomKey = Data(hex: "daaa69f872987f5f5d97fe64b7ab3ebabd3f6865f149b8db41413404d0639798")!
private let goldenServiceName = "6B1F2C8E-3D4A-4F5B-9C7D-8E9F0A1B2C3D"
private let goldenJSON = #"{"app":"meshchat","key":"2qpp+HKYf19dl/5kt6s+ur0/aGXxSbjbQUE0BNBjl5g=","svc":"6B1F2C8E-3D4A-4F5B-9C7D-8E9F0A1B2C3D","v":1}"#

@Suite("RoomInvite QR codec")
struct RoomInviteTests {

    // MARK: — Контрольная строка §6.4

    @Test("qrPayload() совпадает с контрольной строкой §6.4")
    func goldenQRString() throws {
        let invite = RoomInvite(version: 1, serviceName: goldenServiceName, roomKey: goldenRoomKey)
        let payload = try invite.qrPayload()
        #expect(payload == goldenJSON)
    }

    // MARK: — Roundtrip

    @Test("parse(qrPayload:) восстанавливает оригинальное приглашение")
    func roundtrip() throws {
        let original = RoomInvite(version: 1, serviceName: goldenServiceName, roomKey: goldenRoomKey)
        let payload = try original.qrPayload()
        let parsed = try RoomInvite.parse(qrPayload: payload)
        #expect(parsed.version == original.version)
        #expect(parsed.serviceName == original.serviceName)
        #expect(parsed.roomKey == original.roomKey)
    }

    // MARK: — Ошибки разбора

    @Test("не-JSON строка → notMeshChatCode")
    func notJSON() {
        #expect(throws: InviteError.notMeshChatCode) {
            try RoomInvite.parse(qrPayload: "not-a-json-payload")
        }
    }

    @Test("app != meshchat → notMeshChatCode")
    func wrongApp() {
        let json = #"{"app":"other","key":"2qpp+HKYf19dl/5kt6s+ur0/aGXxSbjbQUE0BNBjl5g=","svc":"6B1F2C8E-3D4A-4F5B-9C7D-8E9F0A1B2C3D","v":1}"#
        #expect(throws: InviteError.notMeshChatCode) {
            try RoomInvite.parse(qrPayload: json)
        }
    }

    @Test("svc не UUID → notMeshChatCode")
    func notUUIDServiceName() {
        let json = #"{"app":"meshchat","key":"2qpp+HKYf19dl/5kt6s+ur0/aGXxSbjbQUE0BNBjl5g=","svc":"not-a-uuid","v":1}"#
        #expect(throws: InviteError.notMeshChatCode) {
            try RoomInvite.parse(qrPayload: json)
        }
    }

    @Test("v != 1 → unsupportedVersion")
    func unsupportedVersion() {
        let json = #"{"app":"meshchat","key":"2qpp+HKYf19dl/5kt6s+ur0/aGXxSbjbQUE0BNBjl5g=","svc":"6B1F2C8E-3D4A-4F5B-9C7D-8E9F0A1B2C3D","v":2}"#
        #expect(throws: InviteError.unsupportedVersion(2)) {
            try RoomInvite.parse(qrPayload: json)
        }
    }

    @Test("key не 32 байта → invalidKey")
    func shortKey() {
        // base64 из 16 байт
        let shortKey = Data(count: 16).base64EncodedString()
        let json = #"{"app":"meshchat","key":"\#(shortKey)","svc":"6B1F2C8E-3D4A-4F5B-9C7D-8E9F0A1B2C3D","v":1}"#
        #expect(throws: InviteError.invalidKey) {
            try RoomInvite.parse(qrPayload: json)
        }
    }
}

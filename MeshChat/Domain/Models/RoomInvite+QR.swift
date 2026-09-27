// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

// MARK: - QR payload codec (§6.4)

nonisolated private struct QRPayload: Codable {
    let app: String
    let v: Int
    let svc: String
    let key: Data
}

extension RoomInvite {

    /// Кодирует приглашение в детерминированный JSON-строку для QR-кода.
    /// Ключи отсортированы; data — base64; UTF-8.
    nonisolated func qrPayload() throws -> String {
        let payload = QRPayload(app: "meshchat", v: version, svc: serviceName, key: roomKey)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        // JSONEncoder гарантирует UTF-8 — nil невозможен
        guard let string = String(data: data, encoding: .utf8) else {
            throw InviteError.notMeshChatCode
        }
        return string
    }

    /// Разбирает QR-строку и возвращает приглашение, либо бросает `InviteError`.
    nonisolated static func parse(qrPayload: String) throws -> RoomInvite {
        guard let data = qrPayload.data(using: .utf8) else {
            throw InviteError.notMeshChatCode
        }
        let payload: QRPayload
        do {
            payload = try JSONDecoder().decode(QRPayload.self, from: data)
        } catch {
            throw InviteError.notMeshChatCode
        }
        guard payload.app == "meshchat", UUID(uuidString: payload.svc) != nil else {
            throw InviteError.notMeshChatCode
        }
        guard payload.v == RoomInvite.currentVersion else {
            throw InviteError.unsupportedVersion(payload.v)
        }
        guard payload.key.count == 32 else {
            throw InviteError.invalidKey
        }
        return RoomInvite(version: payload.v, serviceName: payload.svc, roomKey: payload.key)
    }
}

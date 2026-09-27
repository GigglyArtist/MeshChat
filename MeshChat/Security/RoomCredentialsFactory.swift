// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import CryptoKit

/// Создаёт и восстанавливает `RoomCredentials` из пароля или QR-приглашения (§6.3).
nonisolated struct RoomCredentialsFactory: RoomSecretProviding {

    nonisolated private static let hkdfContext = Data("meshchat/room-key/v1".utf8)

    func makeSecret(password: String) -> any RoomSecret {
        // salt = 32 случайных байта из SymmetricKey(size: .bits256) — §6.3
        let saltKey = SymmetricKey(size: .bits256)
        let salt = saltKey.withUnsafeBytes { Data($0) }
        let roomKey = RoomCredentialsFactory.deriveRoomKey(password: password, salt: salt)
        // deriveRoomKey гарантирует ровно 32 байта — RoomCredentials.init никогда не бросит
        do {
            return try RoomCredentials(roomKeyData: roomKey)
        } catch {
            fatalError("deriveRoomKey guarantees 32 bytes: \(error)")
        }
    }

    func secret(from invite: RoomInvite) throws -> any RoomSecret {
        try RoomCredentials(roomKeyData: invite.roomKey)
    }

    /// HKDF-SHA256: из пароля (UTF-8) и соли получает 32-байтовый ключ комнаты — §6.3.
    static func deriveRoomKey(password: String, salt: Data) -> Data {
        let inputKey = SymmetricKey(data: Data(password.utf8))
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: hkdfContext,
            outputByteCount: 32
        )
        return derived.withUnsafeBytes { Data($0) }
    }
}

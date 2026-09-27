// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import CryptoKit

/// Создаёт и восстанавливает `RoomCredentials` из пароля или QR-приглашения (§6.3).
nonisolated struct RoomCredentialsFactory: RoomSecretProviding {

    private static let hkdfContext: StaticString = "meshchat/room-key/v1"

    func makeSecret(password: String) -> any RoomSecret {
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        let roomKey = RoomCredentialsFactory.deriveRoomKey(password: password, salt: salt)
        // salt не включается в roomKeyData — ключ уже финальный
        return try! RoomCredentials(roomKeyData: roomKey) // 32 байта гарантированы
    }

    func secret(from invite: RoomInvite) throws -> any RoomSecret {
        try RoomCredentials(roomKeyData: invite.roomKey)
    }

    /// HKDF-SHA256: из пароля (UTF-8) и случайной соли получает 32-байтовый ключ.
    static func deriveRoomKey(password: String, salt: Data) -> Data {
        let passwordData = Data(password.utf8)
        let inputKey = SymmetricKey(data: passwordData)
        let context = hkdfContext.withUTF8Buffer { Data($0) }
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: context,
            outputByteCount: 32
        )
        return Data(derived.withUnsafeBytes { $0 })
    }
}

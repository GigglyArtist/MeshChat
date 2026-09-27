// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import CryptoKit

/// Секрет комнаты — набор ключей, выведенных из 32-байтового `roomKeyData` (§6.3).
/// Живёт только в памяти, никогда не сериализуется.
nonisolated struct RoomCredentials: RoomSecret {

    // Data — Sendable и неизменяем после инициализации static let: доступ из любого контекста безопасен.
    nonisolated(unsafe) private static let tlsPSKData = Data("meshchat/tls-psk/v1".utf8)
    nonisolated(unsafe) private static let authContextPrefix = "meshchat/auth/v1|"

    let roomKeyData: Data
    let tlsPreSharedKey: Data

    /// - Throws: `InviteError.invalidKey` если `roomKeyData` не 32 байта.
    init(roomKeyData: Data) throws {
        guard roomKeyData.count == 32 else { throw InviteError.invalidKey }
        self.roomKeyData = roomKeyData

        // tlsPSK = HMAC<SHA256>(key: roomKey, data: "meshchat/tls-psk/v1") — §6.3
        let masterKey = SymmetricKey(data: roomKeyData)
        self.tlsPreSharedKey = Data(
            HMAC<SHA256>.authenticationCode(for: RoomCredentials.tlsPSKData, using: masterKey)
        )
    }

    func authToken(for peerID: UUID) -> Data {
        // authToken = HMAC<SHA256>(key: roomKey, data: "meshchat/auth/v1|" + peerID.uuidString) — §6.3
        let masterKey = SymmetricKey(data: roomKeyData)
        let message = Data((RoomCredentials.authContextPrefix + peerID.uuidString).utf8)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: masterKey))
    }

    func isValidAuthToken(_ token: Data, for peerID: UUID) -> Bool {
        let masterKey = SymmetricKey(data: roomKeyData)
        let message = Data((RoomCredentials.authContextPrefix + peerID.uuidString).utf8)
        return HMAC<SHA256>.isValidAuthenticationCode(token, authenticating: message, using: masterKey)
    }
}

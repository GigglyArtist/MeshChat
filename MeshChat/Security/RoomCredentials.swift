// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import CryptoKit

/// Секрет комнаты — набор ключей, выведенных из 32-байтового `roomKeyData` (§6.3).
/// Живёт только в памяти, никогда не сериализуется.
nonisolated struct RoomCredentials: RoomSecret {

    private static let tlsContext: StaticString = "meshchat/tls-psk/v1"
    private static let authContext: StaticString = "meshchat/auth-token/v1"

    let roomKeyData: Data
    let tlsPreSharedKey: Data

    /// - Throws: `InviteError.invalidKey` если `roomKeyData` не 32 байта.
    init(roomKeyData: Data) throws {
        guard roomKeyData.count == 32 else { throw InviteError.invalidKey }
        self.roomKeyData = roomKeyData

        let masterKey = SymmetricKey(data: roomKeyData)
        let tlsContext = RoomCredentials.tlsContext
        let tlsData = tlsContext.withUTF8Buffer { Data($0) }
        self.tlsPreSharedKey = Data(
            HKDF<SHA256>.deriveKey(
                inputKeyMaterial: masterKey,
                info: tlsData,
                outputByteCount: 32
            ).withUnsafeBytes { $0 }
        )
    }

    func authToken(for peerID: UUID) -> Data {
        let masterKey = SymmetricKey(data: roomKeyData)
        let authContext = RoomCredentials.authContext
        let contextData = authContext.withUTF8Buffer { Data($0) }
        let tokenKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            info: contextData,
            outputByteCount: 32
        )
        var message = peerID.data
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: tokenKey)
        return Data(mac)
    }

    func isValidAuthToken(_ token: Data, for peerID: UUID) -> Bool {
        let masterKey = SymmetricKey(data: roomKeyData)
        let authContext = RoomCredentials.authContext
        let contextData = authContext.withUTF8Buffer { Data($0) }
        let tokenKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            info: contextData,
            outputByteCount: 32
        )
        let message = peerID.data
        return HMAC<SHA256>.isValidAuthenticationCode(token, authenticating: message, using: tokenKey)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

// Соль: байты 0x00…0x1f; peerID из §6.3 контрольных значений
private let goldenSalt = Data(0x00...0x1f)
private let goldenPeerID = UUID(uuidString: "0F8E4A4C-6C7B-4E36-9F37-2B0B7B0F6A11")!

@Suite("RoomCredentials")
struct RoomCredentialsTests {

    // MARK: — Контрольные значения §6.3

    @Test("correct horse — roomKey, tlsPSK, authToken совпадают с §6.3")
    func goldenVectorCorrectHorse() throws {
        let roomKey = try #require(Data(hex: "daaa69f872987f5f5d97fe64b7ab3ebabd3f6865f149b8db41413404d0639798"))
        let expectedTLS = try #require(Data(hex: "5b5d095ba4be7c00317ad22287331e2aa89047f90000216b21daa68ae4ad74ea"))
        let expectedAuth = try #require(Data(hex: "6671cee409443c8c4c39995a5a53f191a04c3187efdcdbf2022dbda6999b6e19"))

        // Проверяем deriveRoomKey
        let derivedKey = RoomCredentialsFactory.deriveRoomKey(password: "correct horse", salt: goldenSalt)
        #expect(derivedKey == roomKey)

        let credentials = try RoomCredentials(roomKeyData: derivedKey)
        #expect(credentials.tlsPreSharedKey == expectedTLS)
        #expect(credentials.authToken(for: goldenPeerID) == expectedAuth)
    }

    @Test("пароль1234 (кириллица) — roomKey, tlsPSK, authToken совпадают с §6.3")
    func goldenVectorCyrillic() throws {
        let roomKey = try #require(Data(hex: "cef560cb64a7e34b7933bdeec0ecef23050e5b78f291e40b3bbd50a35b46e72f"))
        let expectedTLS = try #require(Data(hex: "dd0f870b294ec9eaeebea44010d701725f8ff9fe66cc7e91727d198fec823a0d"))
        let expectedAuth = try #require(Data(hex: "4c8d08408f6969405ac78f730a9d77b2693e7994f5f19478b40a85003d936179"))

        let derivedKey = RoomCredentialsFactory.deriveRoomKey(password: "пароль1234", salt: goldenSalt)
        #expect(derivedKey == roomKey)

        let credentials = try RoomCredentials(roomKeyData: derivedKey)
        #expect(credentials.tlsPreSharedKey == expectedTLS)
        #expect(credentials.authToken(for: goldenPeerID) == expectedAuth)
    }

    // MARK: — Детерминизм

    @Test("одна соль → одинаковый ключ")
    func deterministicKey() throws {
        let key1 = RoomCredentialsFactory.deriveRoomKey(password: "test", salt: goldenSalt)
        let key2 = RoomCredentialsFactory.deriveRoomKey(password: "test", salt: goldenSalt)
        #expect(key1 == key2)
    }

    @Test("разные соли → разные ключи")
    func differentSaltsDifferentKeys() throws {
        let salt2 = Data(repeating: 0xFF, count: 32)
        let key1 = RoomCredentialsFactory.deriveRoomKey(password: "test", salt: goldenSalt)
        let key2 = RoomCredentialsFactory.deriveRoomKey(password: "test", salt: salt2)
        #expect(key1 != key2)
    }

    // MARK: — authToken

    @Test("валидный токен проходит isValidAuthToken")
    func validTokenAccepted() throws {
        let roomKey = RoomCredentialsFactory.deriveRoomKey(password: "abc123", salt: goldenSalt)
        let credentials = try RoomCredentials(roomKeyData: roomKey)
        let peerID = UUID()
        let token = credentials.authToken(for: peerID)
        #expect(credentials.isValidAuthToken(token, for: peerID))
    }

    @Test("токен другого участника отклоняется")
    func wrongPeerTokenRejected() throws {
        let roomKey = RoomCredentialsFactory.deriveRoomKey(password: "abc123", salt: goldenSalt)
        let credentials = try RoomCredentials(roomKeyData: roomKey)
        let token = credentials.authToken(for: UUID())
        #expect(!credentials.isValidAuthToken(token, for: UUID()))
    }

    // MARK: — Инициализация

    @Test("init с ключом не 32 байта бросает InviteError.invalidKey")
    func invalidKeySizeThrows() {
        #expect(throws: InviteError.invalidKey) {
            try RoomCredentials(roomKeyData: Data(count: 16))
        }
    }
}

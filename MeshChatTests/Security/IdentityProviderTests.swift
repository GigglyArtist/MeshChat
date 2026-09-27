// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

@Suite("IdentityProvider", .serialized)
struct IdentityProviderTests {

    private func makeProvider() -> (IdentityProvider, FakeKeychainStore) {
        let keychain = FakeKeychainStore()
        return (IdentityProvider(keychain: keychain), keychain)
    }

    @Test("PermanentPeerID генерируется один раз и стабилен при повторных вызовах")
    func permanentPeerIDStable() throws {
        let (provider, _) = makeProvider()
        let id1 = try provider.permanentPeerID()
        let id2 = try provider.permanentPeerID()
        #expect(id1 == id2)
    }

    @Test("Два экземпляра с общим Keychain возвращают одинаковый PermanentPeerID")
    func permanentPeerIDSharedKeychain() throws {
        let keychain = FakeKeychainStore()
        let first = IdentityProvider(keychain: keychain)
        let second = IdentityProvider(keychain: keychain)
        let id1 = try first.permanentPeerID()
        let id2 = try second.permanentPeerID()
        #expect(id1 == id2)
    }

    @Test("До setNickname nickname() возвращает nil")
    func nicknameInitiallyNil() {
        let (provider, _) = makeProvider()
        #expect(provider.nickname() == nil)
    }

    @Test("setNickname сохраняет нормализованный ник")
    func setNicknameStores() throws {
        let (provider, _) = makeProvider()
        try provider.setNickname("  Alice  ")
        #expect(provider.nickname() == "Alice")
    }

    @Test("setNickname повторно обновляет ник")
    func setNicknameUpdate() throws {
        let (provider, _) = makeProvider()
        try provider.setNickname("Alice")
        try provider.setNickname("Bob")
        #expect(provider.nickname() == "Bob")
    }

    @Test("setNickname пустой строки бросает invalidNickname")
    func setNicknameEmpty() {
        let (provider, _) = makeProvider()
        #expect(throws: IdentityError.invalidNickname) {
            try provider.setNickname("   ")
        }
    }

    @Test("setNickname слишком длинного ника бросает invalidNickname")
    func setNicknameTooLong() {
        let (provider, _) = makeProvider()
        #expect(throws: IdentityError.invalidNickname) {
            try provider.setNickname(String(repeating: "x", count: 33))
        }
    }

    @Test("corruptedIdentity при не-16-байтных данных в Keychain")
    func corruptedIdentity() throws {
        let keychain = FakeKeychainStore()
        try keychain.add(Data([0x01, 0x02]), account: "permanentPeerID")
        let provider = IdentityProvider(keychain: keychain)
        #expect(throws: IdentityError.corruptedIdentity) {
            try provider.permanentPeerID()
        }
    }
}

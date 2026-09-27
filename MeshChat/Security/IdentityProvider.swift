// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Реализует IdentityProviding поверх Keychain (§6.1–6.2).
///
/// `@unchecked Sendable` безопасен: единственное хранимое свойство `keychain` неизменяемо (`let`);
/// операции Keychain потокобезопасны на уровне OS.
nonisolated final class IdentityProvider: IdentityProviding, @unchecked Sendable {

    // MARK: - Keychain account keys

    private enum Keys {
        static let permanentPeerID = "permanentPeerID"
        static let nickname = "nickname"
    }

    private let keychain: any KeychainStoring

    nonisolated init(keychain: any KeychainStoring) {
        self.keychain = keychain
    }

    // MARK: - IdentityProviding

    nonisolated func permanentPeerID() throws -> UUID {
        // Читаем существующий PermanentPeerID
        do {
            if let data = try keychain.read(account: Keys.permanentPeerID) {
                guard let uuid = UUID(data: data) else { throw IdentityError.corruptedIdentity }
                return uuid
            }
        } catch KeychainError.unexpectedStatus(let status) {
            throw IdentityError.keychain(status: status)
        }
        // Первый запуск: генерируем и пытаемся записать
        let new = UUID()
        do {
            try keychain.add(new.data, account: Keys.permanentPeerID)
            return new
        } catch KeychainError.duplicateItem {
            // Гонка: другой вызов успел записать раньше — перечитываем
            guard let data = try? keychain.read(account: Keys.permanentPeerID),
                  let uuid = UUID(data: data) else {
                throw IdentityError.corruptedIdentity
            }
            return uuid
        } catch KeychainError.unexpectedStatus(let status) {
            throw IdentityError.keychain(status: status)
        }
    }

    nonisolated func nickname() -> String? {
        guard let data = try? keychain.read(account: Keys.nickname),
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    nonisolated func setNickname(_ nickname: String) throws {
        guard let normalized = NicknamePolicy.normalize(nickname) else {
            throw IdentityError.invalidNickname
        }
        guard let data = normalized.data(using: .utf8) else {
            throw IdentityError.invalidNickname
        }
        do {
            try keychain.delete(account: Keys.nickname)
            try keychain.add(data, account: Keys.nickname)
        } catch KeychainError.unexpectedStatus(let status) {
            throw IdentityError.keychain(status: status)
        }
    }
}

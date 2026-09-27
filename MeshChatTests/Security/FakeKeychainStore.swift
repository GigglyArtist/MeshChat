// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковый Keychain для юнит-тестов: хранит данные в памяти.
///
/// `@unchecked Sendable` безопасен: используется только в последовательных тестах (`.serialized`).
final class FakeKeychainStore: KeychainStoring, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func read(account: String) throws -> Data? {
        store[account]
    }

    func add(_ data: Data, account: String) throws {
        guard store[account] == nil else { throw KeychainError.duplicateItem }
        store[account] = data
    }

    func delete(account: String) throws {
        store.removeValue(forKey: account)
    }
}

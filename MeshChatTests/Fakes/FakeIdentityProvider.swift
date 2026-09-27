// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковый IdentityProviding для тестов ViewModel: хранит данные в памяти.
///
/// `@unchecked Sendable` безопасен: используется только в `@MainActor`-тестах
/// с `.serialized`, где нет параллельного доступа.
final class FakeIdentityProvider: IdentityProviding, @unchecked Sendable {

    private let storedID = UUID()
    var storedNickname: String?
    /// Если задана — `setNickname` бросает эту ошибку.
    var nicknameToThrow: Error?
    private(set) var setNicknameCalls: [String] = []

    init(nickname: String? = nil) {
        storedNickname = nickname
    }

    func permanentPeerID() throws -> UUID { storedID }

    func nickname() -> String? { storedNickname }

    func setNickname(_ nickname: String) throws {
        if let error = nicknameToThrow { throw error }
        setNicknameCalls.append(nickname)
        storedNickname = NicknamePolicy.normalize(nickname)
    }
}

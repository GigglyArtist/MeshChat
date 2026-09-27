// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

#if DEBUG
import Foundation

/// Фейковый IdentityProviding для SwiftUI Previews: хранит данные в памяти.
///
/// `@unchecked Sendable` безопасен: используется только в однопоточном контексте Preview.
nonisolated final class PreviewIdentityProvider: IdentityProviding, @unchecked Sendable {

    private let storedID = UUID()
    private var storedNickname: String?

    nonisolated init(nickname: String? = nil) {
        self.storedNickname = nickname
    }

    nonisolated func permanentPeerID() throws -> UUID { storedID }

    nonisolated func nickname() -> String? { storedNickname }

    nonisolated func setNickname(_ nickname: String) throws {
        guard let normalized = NicknamePolicy.normalize(nickname) else {
            throw IdentityError.invalidNickname
        }
        storedNickname = normalized
    }
}
#endif

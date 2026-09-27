// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Постоянная личность устройства (§6.1).
protocol IdentityProviding: Sendable {

    /// Возвращает PermanentPeerID. При первом вызове генерирует UUID и сохраняет в Keychain.
    /// Безопасен при одновременных вызовах: всегда возвращает значение, реально лежащее в Keychain.
    nonisolated func permanentPeerID() throws -> UUID

    /// Никнейм или `nil`, если онбординг ещё не пройден.
    nonisolated func nickname() -> String?

    /// Сохраняет никнейм (нормализует через `NicknamePolicy`).
    /// Бросает `IdentityError.invalidNickname`, если результат пустой или длиннее 32 символов.
    nonisolated func setNickname(_ nickname: String) throws
}

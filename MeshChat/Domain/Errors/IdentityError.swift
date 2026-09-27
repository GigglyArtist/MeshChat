// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Ошибки слоя идентичности (§14.1).
nonisolated enum IdentityError: Error, Sendable, Equatable {
    /// Операция Keychain вернула неожиданный статус.
    case keychain(status: Int32)
    /// В Keychain лежат данные, не являющиеся 16-байтным UUID.
    case corruptedIdentity
    /// Никнейм не прошёл валидацию `NicknamePolicy`.
    case invalidNickname
}

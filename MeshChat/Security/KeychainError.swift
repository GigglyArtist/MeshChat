// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Внутренняя ошибка слоя Security при работе с Keychain (§14.1).
nonisolated enum KeychainError: Error, Sendable, Equatable {
    /// Элемент с таким `account` уже существует.
    case duplicateItem
    /// Security.framework вернул неожиданный статус.
    case unexpectedStatus(Int32)
}

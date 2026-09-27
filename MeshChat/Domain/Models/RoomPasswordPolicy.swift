// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Политика пароля комнаты (§6.3). Без обрезки пробелов — это работа пользователя.
nonisolated enum RoomPasswordPolicy {
    static let minLength = 4
    static let maxLength = 64

    /// `true` если длина в символах 4…64 и строка не состоит только из пробелов.
    static func isValid(_ password: String) -> Bool {
        let count = password.count
        guard count >= minLength, count <= maxLength else { return false }
        return !password.allSatisfy(\.isWhitespace)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Правила валидации и нормализации текста чат-сообщений (§5.2).
nonisolated enum MessageTextPolicy {

    /// Максимальная длина текста в символах Unicode.
    static let maxLength = 4_000

    /// Нормализует строку: обрезает пробельные символы по краям.
    ///
    /// Возвращает `nil`, если результат пуст или длиннее `maxLength` символов.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        return trimmed
    }
}

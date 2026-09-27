// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Единое правило нормализации никнейма для Identity, Session и UI (§6.1).
nonisolated enum NicknamePolicy {
    /// Максимальная длина никнейма в символах Unicode.
    static let maxLength = 32

    /// Обрезает пробелы и переводы строк по краям.
    /// Возвращает `nil`, если результат пустой или длиннее `maxLength` символов.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        return trimmed
    }
}

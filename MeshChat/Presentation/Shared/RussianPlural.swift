// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Вспомогательный тип для склонения русских существительных по числу.
enum RussianPlural {
    /// Возвращает нужную форму слова для числа `n`.
    /// - one: 1, 21, 31, ... (кроме 11)
    /// - few: 2–4, 22–24, ... (кроме 12–14)
    /// - many: 0, 5–20, 11–14, 25–30, ...
    static func word(for n: Int, one: String, few: String, many: String) -> String {
        let rem100 = abs(n) % 100
        let rem10 = abs(n) % 10
        if rem100 >= 11 && rem100 <= 19 { return many }
        switch rem10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }
}

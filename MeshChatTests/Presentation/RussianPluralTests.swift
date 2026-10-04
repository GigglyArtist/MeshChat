// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
@testable import MeshChat

@Suite("RussianPluralTests")
struct RussianPluralTests {

    @Test("correct plural form for чат/чата/чатов", arguments: [
        (1, "чат"),
        (2, "чата"),
        (5, "чатов"),
        (11, "чатов"),
        (12, "чатов"),
        (14, "чатов"),
        (21, "чат"),
        (22, "чата"),
        (25, "чатов"),
        (111, "чатов"),
        (0, "чатов")
    ] as [(Int, String)])
    func pluralForm(n: Int, expected: String) {
        let result = RussianPlural.word(for: n, one: "чат", few: "чата", many: "чатов")
        #expect(result == expected, "n=\(n): expected '\(expected)', got '\(result)'")
    }
}

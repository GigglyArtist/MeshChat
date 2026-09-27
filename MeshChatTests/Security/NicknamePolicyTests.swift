// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
@testable import MeshChat

@Suite("NicknamePolicy")
struct NicknamePolicyTests {

    @Test("Валидный ник возвращается без изменений")
    func validNickname() {
        #expect(NicknamePolicy.normalize("Alice") == "Alice")
    }

    @Test("Пробелы по краям обрезаются")
    func trimsWhitespace() {
        #expect(NicknamePolicy.normalize("  Bob  ") == "Bob")
    }

    @Test("Перевод строки по краям обрезается")
    func trimsNewlines() {
        #expect(NicknamePolicy.normalize("\nCharlie\n") == "Charlie")
    }

    @Test("Пустая строка → nil")
    func emptyString() {
        #expect(NicknamePolicy.normalize("") == nil)
    }

    @Test("Строка только из пробелов → nil")
    func whitespaceOnly() {
        #expect(NicknamePolicy.normalize("   ") == nil)
    }

    @Test("32 символа — максимально допустимо")
    func exactMaxLength() {
        let name = String(repeating: "x", count: 32)
        #expect(NicknamePolicy.normalize(name) == name)
    }

    @Test("33 символа → nil")
    func tooLong() {
        let name = String(repeating: "x", count: 33)
        #expect(NicknamePolicy.normalize(name) == nil)
    }

    @Test("Эмодзи считаются как один символ каждый")
    func emojiCount() {
        let name = String(repeating: "😀", count: 32)
        #expect(NicknamePolicy.normalize(name) == name)
    }
}

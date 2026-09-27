// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
@testable import MeshChat

@Suite("RoomPasswordPolicy")
struct RoomPasswordPolicyTests {

    @Test("3 символа — недопустимо", arguments: ["abc"])
    func tooShort(_ password: String) {
        #expect(!RoomPasswordPolicy.isValid(password))
    }

    @Test("4 символа — минимально допустимо", arguments: ["abcd"])
    func minLength(_ password: String) {
        #expect(RoomPasswordPolicy.isValid(password))
    }

    @Test("64 символа — максимально допустимо")
    func maxLength() {
        let password = String(repeating: "a", count: 64)
        #expect(RoomPasswordPolicy.isValid(password))
    }

    @Test("65 символов — недопустимо")
    func tooLong() {
        let password = String(repeating: "a", count: 65)
        #expect(!RoomPasswordPolicy.isValid(password))
    }

    @Test("строка из одних пробелов — недопустимо", arguments: ["    "])
    func allSpaces(_ password: String) {
        #expect(!RoomPasswordPolicy.isValid(password))
    }

    @Test("пробелы внутри валидной строки — допустимо", arguments: [" a b"])
    func spacesInsideValid(_ password: String) {
        #expect(RoomPasswordPolicy.isValid(password))
    }
}

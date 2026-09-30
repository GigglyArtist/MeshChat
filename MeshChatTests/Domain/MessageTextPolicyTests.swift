// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

@Suite("MessageTextPolicy")
struct MessageTextPolicyTests {

    // MARK: - Граничные значения длины

    @Test("empty string returns nil")
    func emptyString() {
        #expect(MessageTextPolicy.normalize("") == nil)
    }

    @Test("whitespace-only string returns nil")
    func whitespaceOnly() {
        #expect(MessageTextPolicy.normalize("   \n\t  ") == nil)
    }

    @Test("single character returns it")
    func singleChar() {
        #expect(MessageTextPolicy.normalize("x") == "x")
    }

    @Test("4000 chars accepted")
    func maxLengthAccepted() {
        let text = String(repeating: "a", count: 4_000)
        #expect(MessageTextPolicy.normalize(text) == text)
    }

    @Test("4001 chars rejected")
    func overMaxLengthRejected() {
        let text = String(repeating: "a", count: 4_001)
        #expect(MessageTextPolicy.normalize(text) == nil)
    }

    // MARK: - Обрезка пробелов

    @Test("leading/trailing whitespace trimmed")
    func trimmingWhitespace() {
        #expect(MessageTextPolicy.normalize("  hello  ") == "hello")
    }

    @Test("trim makes string empty → nil")
    func trimResultsInEmpty() {
        #expect(MessageTextPolicy.normalize("  \n  ") == nil)
    }

    @Test("internal whitespace preserved")
    func internalWhitespacePreserved() {
        let text = "hello   world"
        #expect(MessageTextPolicy.normalize(text) == text)
    }

    // MARK: - Параметризованный тест: граничные длины после обрезки

    @Test("length boundary after trimming", arguments: [
        ("  " + String(repeating: "b", count: 4_000) + "  ", 4_000),
        ("  " + String(repeating: "b", count: 4_001) + "  ", nil as Int?),
    ])
    func lengthBoundaryAfterTrimming(raw: String, expectedCount: Int?) {
        let result = MessageTextPolicy.normalize(raw)
        #expect(result?.count == expectedCount)
    }

    // MARK: - Date.flooredToMilliseconds

    @Test("123.999ms timestamp floors to 123ms")
    func flooredToMilliseconds() {
        let t = Date(timeIntervalSince1970: 0.123_999)
        let floored = t.flooredToMilliseconds
        let ms = Int64(floored.timeIntervalSince1970 * 1_000)
        #expect(ms == 123)
    }

    @Test("whole millisecond unchanged")
    func wholeMillisecondUnchanged() {
        let t = Date(timeIntervalSince1970: 1_790_412_345.123)
        let floored = t.flooredToMilliseconds
        let ms = Int64(floored.timeIntervalSince1970 * 1_000)
        #expect(ms == 1_790_412_345_123)
    }
}

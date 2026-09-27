// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

@Suite("KeychainStore", .serialized)
struct KeychainStoreTests {
    // Уникальный service на каждый тест (Swift Testing создаёт новый экземпляр структуры),
    // чтобы не конфликтовать с реальными данными и между тестами.
    private let service = "com.meshchat.test.\(UUID().uuidString)"

    private func makeStore() -> KeychainStore {
        KeychainStore(service: service)
    }

    @Test("read возвращает nil для несуществующего элемента")
    func readMissing() throws {
        #expect(try makeStore().read(account: "absent") == nil)
    }

    @Test("add и read возвращают одинаковые данные")
    func addAndRead() throws {
        let store = makeStore()
        let data = Data([1, 2, 3])
        try store.add(data, account: "key")
        #expect(try store.read(account: "key") == data)
    }

    @Test("повторный add бросает duplicateItem")
    func addDuplicate() throws {
        let store = makeStore()
        try store.add(Data([1]), account: "dup")
        #expect(throws: KeychainError.duplicateItem) {
            try store.add(Data([2]), account: "dup")
        }
    }

    @Test("delete удаляет элемент")
    func deleteItem() throws {
        let store = makeStore()
        try store.add(Data([1]), account: "del")
        try store.delete(account: "del")
        #expect(try store.read(account: "del") == nil)
    }

    @Test("delete несуществующего элемента не бросает ошибку")
    func deleteMissing() throws {
        #expect(throws: Never.self) {
            try makeStore().delete(account: "ghost")
        }
    }
}

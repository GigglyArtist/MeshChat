// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Тонкая обёртка над Security.framework (kSecClassGenericPassword).
/// Нужна для подмены в тестах (§6.1).
protocol KeychainStoring: Sendable {

    /// Данные элемента или `nil`, если элемента нет.
    nonisolated func read(account: String) throws -> Data?

    /// Добавляет элемент. Существующий **не** перезаписывает: бросает `KeychainError.duplicateItem`.
    nonisolated func add(_ data: Data, account: String) throws

    /// Удаляет элемент. Если элемент не существует — не бросает ошибку.
    nonisolated func delete(account: String) throws
}

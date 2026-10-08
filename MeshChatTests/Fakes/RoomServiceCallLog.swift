// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Общий журнал вызовов для проверки порядка событий в тестах `RoomService`.
///
/// Потокобезопасен: `NSLock` защищает мутируемый массив записей.
/// Используется только в тестовом коде.
final class RoomServiceCallLog: @unchecked Sendable {

    private let lock = NSLock()
    private var _entries: [String] = []

    /// Все записи в порядке поступления.
    var entries: [String] { lock.withLock { _entries } }

    func append(_ entry: String) { lock.withLock { _entries.append(entry) } }
}

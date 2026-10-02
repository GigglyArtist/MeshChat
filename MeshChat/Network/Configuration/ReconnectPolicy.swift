// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Стратегия паузы между попытками переподключения клиента (§9.4).
///
/// Возвращает паузу для попытки номер `n`: первые элементы `backoff` используются
/// по порядку; после исчерпания массива возвращается последний элемент.
nonisolated struct ReconnectPolicy: Sendable {

    private let backoff: [Duration]

    /// - Precondition: `backoff` не пустой.
    init(backoff: [Duration]) {
        precondition(!backoff.isEmpty, "ReconnectPolicy requires at least one interval")
        self.backoff = backoff
    }

    /// Пауза перед `attempt`-й попыткой (счёт с 1).
    ///
    /// - attempt 1 → `backoff[0]`
    /// - attempt n > `backoff.count` → `backoff.last`
    func delay(forAttempt attempt: Int) -> Duration {
        let index = max(0, min(attempt - 1, backoff.count - 1))
        return backoff[index]
    }
}

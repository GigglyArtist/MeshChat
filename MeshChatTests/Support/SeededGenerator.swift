// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Детерминированный генератор псевдослучайных чисел SplitMix64.
///
/// Используется в тестах для воспроизводимого разбиения данных на чанки.
struct SeededGenerator: RandomNumberGenerator {

    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

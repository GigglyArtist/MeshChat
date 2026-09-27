// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

extension Data {
    /// Инициализирует `Data` из hex-строки (без пробелов, чётная длина).
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }

    /// Hex-представление в нижнем регистре.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

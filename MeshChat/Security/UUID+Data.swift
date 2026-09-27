// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

extension UUID {
    /// 16-байтное big-endian представление UUID (RFC 4122) для хранения в Keychain.
    nonisolated var data: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }

    /// Инициализирует UUID из ровно 16 байт. Возвращает `nil` при любой другой длине.
    nonisolated init?(data: Data) {
        guard data.count == 16 else { return nil }
        let bytes = data.withUnsafeBytes { $0.load(as: uuid_t.self) }
        self.init(uuid: bytes)
    }
}

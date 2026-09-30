// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

extension Date {
    /// Дата, округлённая вниз до целых миллисекунд.
    ///
    /// Используется при отправке сообщений: локальная копия timestamp совпадает
    /// с тем, что получат участники после JSON-сериализации (§8.2).
    var flooredToMilliseconds: Date {
        let ms = (timeIntervalSince1970 * 1_000).rounded(.down)
        return Date(timeIntervalSince1970: ms / 1_000)
    }
}

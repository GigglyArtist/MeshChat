// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Содержимое QR-приглашения в комнату (§6.3). Codable добавляется в расширении (шаг 6).
nonisolated struct RoomInvite: Sendable {
    static let currentVersion = 1

    /// Версия протокола QR-формата.
    let version: Int
    /// Имя Bonjour-сервиса хоста.
    let serviceName: String
    /// 32-байтовый ключ комнаты.
    let roomKey: Data
}

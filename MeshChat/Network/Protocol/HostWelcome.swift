// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Ответ хоста на валидный `clientHello` (§8.3).
nonisolated struct HostWelcome: Codable, Sendable, Equatable {
    /// Всегда `"success"` (отказ не передаётся пакетом — хост закрывает соединение).
    let status: String
    /// Идентификатор сессии, единый для всех участников.
    let sessionID: UUID
    /// Постоянный идентификатор хоста.
    let hostPermanentPeerID: UUID
    /// Отображаемое имя хоста.
    let hostNickname: String
    /// Остальные уже присутствующие участники (без хоста и без нового клиента).
    let participants: [PeerPayload]
}

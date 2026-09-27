// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Первый пакет клиента после TLS-соединения (§8.3).
nonisolated struct ClientHello: Codable, Sendable, Equatable {
    /// Версия протокола MeshChat, поддерживаемая клиентом.
    let protocolVersion: Int
    /// HMAC-токен, привязанный к permanentPeerID (§6.3).
    let authToken: Data
    /// Постоянный идентификатор устройства клиента.
    let permanentPeerID: UUID
    /// Отображаемое имя клиента.
    let nickname: String
    /// Идентификатор прерванной сессии при переподключении; `nil` при первом входе.
    let resumeSessionID: UUID?
}

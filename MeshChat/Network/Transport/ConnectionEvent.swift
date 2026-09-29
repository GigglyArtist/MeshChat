// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Событие, поступающее из `PeerConnection.events` (§7.3).
nonisolated enum ConnectionEvent: Sendable {
    /// Изменение состояния соединения.
    case state(ConnectionState)
    /// Изменение доступности пути (может меняться независимо от состояния).
    case viability(Bool)
    /// Успешно декодированный входящий пакет.
    case packet(Packet)
    /// Нарушение протокола.
    ///
    /// - `invalidFrameLength`, `malformedJSON`, `unsupportedVersion` — соединение закрывается сразу после события.
    /// - `unknownType` — соединение **не** закрывается: решает вышестоящая сессия (§8.4).
    case protocolViolation(PacketCodecError)
}

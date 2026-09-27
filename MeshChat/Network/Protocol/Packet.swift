// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Все типы пакетов протокола MeshChat (§8.6).
nonisolated enum Packet: Sendable, Equatable {
    case clientHello(ClientHello)
    case hostWelcome(HostWelcome)
    case chatMessage(MessagePayload)
    case participantJoined(PeerPayload)
    case participantLeft(ParticipantLeftPayload)
    case sessionEnded(SessionEndedPayload)
    /// Клиент уходит добровольно; `payload` в проводе — пустой объект `{}` (§8.2).
    case leave
    case ping(HeartbeatPayload)
    case pong(HeartbeatPayload)
}

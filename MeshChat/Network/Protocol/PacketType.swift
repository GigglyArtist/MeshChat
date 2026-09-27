// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Дискриминатор типа пакета в конверте (§8.3, §8.6).
nonisolated enum PacketType: String, Sendable {
    case clientHello
    case hostWelcome
    case chatMessage
    case participantJoined
    case participantLeft
    case sessionEnded
    case leave
    case ping
    case pong
}

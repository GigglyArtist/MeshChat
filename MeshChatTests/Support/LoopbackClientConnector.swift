// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Network
@testable import MeshChat

/// Создаёт `NWPeerConnection` к `127.0.0.1` на заданном порту.
///
/// Используется в интеграционных тестах сессий вместо `BonjourClientConnector`,
/// чтобы обойти Bonjour-резолюцию и подключиться напрямую к `BonjourHostListener`.
nonisolated struct LoopbackClientConnector: ClientConnecting {

    let port: UInt16

    nonisolated func makeConnection(serviceName: String, security: ChannelSecurity) -> any PeerConnection {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            // Невалидный порт не должен возникать в тестах.
            preconditionFailure("LoopbackClientConnector: invalid port \(port)")
        }
        return NWPeerConnection(
            endpoint: .hostPort(host: "127.0.0.1", port: nwPort),
            parameters: .meshChat(security: security)
        )
    }
}

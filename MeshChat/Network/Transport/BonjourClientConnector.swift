// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Network

/// Создаёт исходящее соединение к Bonjour-сервису хоста (§7.4).
///
/// Передаёт `NWEndpoint.service(...)` в `NWPeerConnection` — система разрешает имя сама.
nonisolated struct BonjourClientConnector: ClientConnecting {

    private let configuration: NetworkConfiguration

    nonisolated init(configuration: NetworkConfiguration) {
        self.configuration = configuration
    }

    nonisolated func makeConnection(serviceName: String, security: ChannelSecurity) -> any PeerConnection {
        let endpoint = NWEndpoint.service(
            name: serviceName,
            type: configuration.serviceType,
            domain: "local.",
            interface: nil
        )
        // Соединение возвращается незапущенным; start() вызывает сессия.
        return NWPeerConnection(endpoint: endpoint, parameters: .meshChat(security: security))
    }
}

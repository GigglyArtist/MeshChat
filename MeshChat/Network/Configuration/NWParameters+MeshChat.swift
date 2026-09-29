// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Network

extension NWParameters {
    /// TCP-параметры MeshChat: noDelay, keepalive, peer-to-peer Wi-Fi и опциональный TLS-PSK (§7.4).
    static func meshChat(security: ChannelSecurity) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2

        let parameters: NWParameters
        switch security {
        case .tlsPSK(let psk):
            parameters = NWParameters(tls: .meshChatPSK(psk), tcp: tcp)
        #if DEBUG
        case .plaintext:
            parameters = NWParameters(tls: nil, tcp: tcp)
        #endif
        }
        // Разрешить peer-to-peer Wi-Fi (ADR-01).
        parameters.includePeerToPeer = true
        return parameters
    }
}

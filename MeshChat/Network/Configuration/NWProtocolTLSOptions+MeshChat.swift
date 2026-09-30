// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Network
import os

nonisolated extension NWProtocolTLS.Options {
    // Logger — Sendable struct; nonisolated static let безопасен без nonisolated(unsafe).
    private nonisolated static let tlsLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "meshchat",
        category: "network"
    )
    /// TLS с общим ключом по образцу Apple sample «Building a custom peer-to-peer protocol» (§7.4).
    ///
    /// Identity — строка `"meshchat"` в формате `DispatchData`.
    /// Шифронабор — `TLS_PSK_WITH_AES_128_GCM_SHA256`.
    nonisolated static func meshChatPSK(_ psk: Data) -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()

        let key = psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("meshchat".utf8).withUnsafeBytes { DispatchData(bytes: $0) }

        sec_protocol_options_add_pre_shared_key(
            options.securityProtocolOptions,
            key as __DispatchData,
            identity as __DispatchData
        )

        // Без явного шифронабора TLS-PSK не согласуется.
        // tls_ciphersuite_t — UInt16 в некоторых SDK; принимаем оба варианта через UInt16.
        if let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(options.securityProtocolOptions, suite)
        } else {
            // Шифронабор недоступен — TLS не согласуется: должен поймать тест.
            NWProtocolTLS.Options.tlsLogger.fault("PSK cipher suite TLS_PSK_WITH_AES_128_GCM_SHA256 unavailable on this platform")
        }

        return options
    }
}

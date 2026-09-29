// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Причина сбоя канала — единая для состояний соединения и listener'а (§7.3).
nonisolated enum NetworkIssue: Sendable, Equatable, CustomStringConvertible {
    /// Нет разрешения «Локальная сеть»: `NWError.dns(kDNSServiceErr_PolicyDenied)`.
    case localNetworkDenied
    /// Ошибка TLS-рукопожатия: `NWError.tls(OSStatus)`.
    case tlsFailure(Int32)
    /// Прочие ошибки (строка — для логов).
    case other(String)

    nonisolated var description: String {
        switch self {
        case .localNetworkDenied: return "localNetworkDenied"
        case .tlsFailure(let s): return "tlsFailure(\(s))"
        case .other(let m): return "other(\(m))"
        }
    }
}

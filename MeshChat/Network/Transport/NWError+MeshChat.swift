// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Network

extension NWError {
    /// Переводит `NWError` в унифицированный `NetworkIssue` (§7.3).
    var issue: NetworkIssue {
        switch self {
        case .dns(let code) where code == kDNSServiceErr_PolicyDenied:
            // Пользователь запретил доступ к локальной сети.
            return .localNetworkDenied
        case .tls(let status):
            return .tlsFailure(status)
        default:
            return .other(debugDescription)
        }
    }
}

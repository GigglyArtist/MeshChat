// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Режим защиты транспортного канала (§7.3, ADR-03).
nonisolated enum ChannelSecurity: Sendable {
    /// TLS с общим ключом (pre-shared key), выведенным из `roomKey`.
    case tlsPSK(Data)
    #if DEBUG
    /// Незашифрованное соединение — только для отладки трафика.
    /// В Release-сборке этот вариант не существует.
    case plaintext
    #endif
}

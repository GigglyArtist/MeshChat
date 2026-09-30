// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Состояние жизненного цикла сессии (§5.1).
nonisolated enum SessionState: Sendable, Equatable {
    /// Устанавливается TCP/TLS-соединение с хостом.
    case connecting
    /// Хэндшейк завершён, обмен сообщениями доступен.
    case active
    /// Связь потеряна; ожидание восстановления до указанного времени.
    case reconnecting(deadline: Date)
    /// Сессия завершена.
    case ended(SessionEndReason)
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Ошибки сетевого слоя, видимые слою Application (§14.1).
nonisolated enum NetworkError: Error, Sendable, Equatable {
    /// Listener не смог запуститься.
    case listenerFailed(String)
    /// Нет разрешения «Локальная сеть».
    case localNetworkDenied
    /// Попытка отправить пакет, когда сессия не активна.
    case notActive
    /// Ошибка при отправке пакета в сетевой стек.
    case sendFailed(String)
    /// Нарушение протокола (битый кадр, версия и т. д.).
    case protocolViolation(String)
}

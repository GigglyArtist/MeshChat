// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Ошибки слоя хранилища.
nonisolated enum StorageError: Error, Sendable, Equatable {
    /// Не удалось открыть постоянное хранилище. Строка содержит описание системной ошибки.
    case storeLoadingFailed(String)
    /// Сессия с указанным идентификатором не найдена в хранилище.
    case sessionNotFound(UUID)
    /// Собеседник с указанным идентификатором не найден в хранилище.
    case peerNotFound(UUID)
    /// Ошибка сохранения Core Data. Строка содержит описание системной ошибки.
    case saveFailed(String)
}

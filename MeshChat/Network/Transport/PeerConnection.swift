// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Одна двунаправленная связь с удалённой стороной (§7.3).
///
/// Ничего не знает о содержимом чата — только транспорт.
protocol PeerConnection: AnyObject, Sendable {

    /// Локальный ID соединения. **Не** является PermanentPeerID собеседника.
    nonisolated var connectionID: UUID { get }

    /// Поток событий: состояние, viability, пакеты, нарушения протокола.
    /// Завершается после события `.state(.failed)` или `.state(.cancelled)`.
    nonisolated var events: AsyncStream<ConnectionEvent> { get }

    /// Запускает соединение. Вызывается один раз; повторный вызов не имеет эффекта.
    nonisolated func start()

    /// Отправляет пакет. Завершается, когда данные переданы сетевому стеку (`.contentProcessed`).
    /// Бросает `NetworkError.sendFailed` при ошибке отправки.
    nonisolated func send(_ packet: Packet) async throws

    /// Закрывает соединение. Идемпотентен.
    nonisolated func cancel()
}

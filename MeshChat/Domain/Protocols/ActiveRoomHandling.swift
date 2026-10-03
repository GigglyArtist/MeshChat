// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Запущенная комната с точки зрения UI. Реализация — `actor ActiveRoom` (§11).
///
/// Все требования `nonisolated`: проект настроен с `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// и протокол, объявленный вне Presentation/App, должен явно отказываться от главного актора.
protocol ActiveRoomHandling: AnyObject, Sendable {

    /// Роль локального участника.
    nonisolated var role: SessionRole { get }

    /// `PermanentPeerID` локального участника (нужен для определения «моих» сообщений).
    nonisolated var localPeerID: UUID { get }

    /// Приглашение QR-кода — есть только у хоста; у клиента `nil`.
    nonisolated var invite: RoomInvite? { get }

    /// Единственный поток событий комнаты. Завершается после `.stateChanged(.ended)`.
    nonisolated var events: AsyncStream<RoomEvent> { get }

    /// Отправляет текстовое сообщение.
    ///
    /// - Throws: `NetworkError.notActive`, `NetworkError.invalidMessage`, `NetworkError.sendFailed`.
    nonisolated func send(text: String) async throws

    /// Хост завершает комнату; клиент выходит. Итог — `stateChanged(.ended(.leftByUser))`.
    nonisolated func leave() async

    /// Приложение вернулось на передний план (ADR-11).
    ///
    /// Форвардирует `resumeAfterForeground()` к сетевой сессии.
    nonisolated func appDidBecomeActive() async
}

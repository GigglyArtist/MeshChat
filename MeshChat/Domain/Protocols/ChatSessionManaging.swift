// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Управляет жизненным циклом сессии чата (§7.2).
///
/// Поток `events` завершается при переходе в `.ended`.
protocol ChatSessionManaging: AnyObject, Sendable {

    /// Роль локального участника: `.host` или `.client`.
    nonisolated var role: SessionRole { get }

    /// Поток событий сессии.
    nonisolated var events: AsyncStream<SessionEvent> { get }

    /// Запускает сессию. Для клиента — устанавливает соединение и запускает хэндшейк.
    nonisolated func start() async

    /// Отправляет текстовое сообщение.
    ///
    /// - Throws: `NetworkError.notActive` если сессия не в состоянии `.active`.
    /// - Throws: `NetworkError.invalidMessage` если текст не проходит `MessageTextPolicy`.
    nonisolated func send(text: String) async throws -> ChatMessage

    /// Завершает сессию (отправляет `leave` / `sessionEnded` и закрывает соединения).
    nonisolated func end() async

    /// Вызывается, когда приложение возвращается на передний план (ADR-11).
    ///
    /// Хост: если идёт цикл перезапуска listener'а — немедленно перезапускает без паузы.
    /// Клиент: если идёт цикл переподключения — немедленно делает попытку без паузы.
    /// В остальных случаях — no-op.
    nonisolated func resumeAfterForeground() async
}

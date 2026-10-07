// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Событие активной комнаты, которое ViewModel отображает в UI (§11).
nonisolated enum RoomEvent: Sendable, Equatable {
    /// Состояние сессии изменилось (например, `.active`, `.ended(.hostEnded)`).
    case stateChanged(SessionState)
    /// Список участников обновился; несёт полный текущий список (без себя).
    case participantsChanged([PeerProfile])
    /// Новое сообщение добавлено в ленту чата.
    case messageAppended(ChatMessage)
    /// Служебное уведомление (вход / выход участника).
    case notice(RoomNotice)
    /// Клиент снова вошёл в уже знакомую сессию: сохранённые ранее сообщения (по возрастанию
    /// времени) и участники этой сессии из хранилища — чтобы подписать авторов, даже если они
    /// уже ушли. Выдаётся до любых других событий повторной сессии (§11.1, ADR-12).
    case messagesRestored([ChatMessage], knownPeers: [PeerProfile])
}

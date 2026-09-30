// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Событие сессии, доставляемое слою Application через `AsyncStream` (§7.2).
nonisolated enum SessionEvent: Sendable, Equatable {
    /// Состояние сессии изменилось.
    case stateChanged(SessionState)
    /// Хэндшейк завершён; передаётся `sessionID` от хоста.
    case established(sessionID: UUID)
    /// Новый участник вошёл в комнату.
    case participantJoined(PeerProfile)
    /// Участник покинул комнату.
    case participantLeft(PeerProfile, LeaveReason)
    /// Получено сообщение чата.
    case messageReceived(ChatMessage)
}

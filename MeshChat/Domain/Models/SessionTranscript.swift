// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Сохранённая переписка одной сессии (§11).
nonisolated struct SessionTranscript: Sendable, Hashable {
    /// Метаданные сессии, включая список участников.
    let session: ChatSessionInfo
    /// Сообщения по возрастанию `timestamp`.
    let messages: [ChatMessage]
}

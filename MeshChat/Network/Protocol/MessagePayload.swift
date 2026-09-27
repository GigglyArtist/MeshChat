// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// DTO текстового сообщения чата (§8.3).
nonisolated struct MessagePayload: Codable, Sendable, Equatable {
    let messageID: UUID
    let senderID: UUID
    let text: String
    /// Время создания сообщения у отправителя; кодируется как целые миллисекунды (§8.2).
    let timestamp: Date
}

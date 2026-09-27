// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Ошибки разбора QR-приглашения (§14.1).
nonisolated enum InviteError: Error, Sendable, Equatable {
    /// QR-код не является MeshChat-приглашением (поле `app` не совпадает).
    case notMeshChatCode
    /// Версия протокола не поддерживается.
    case unsupportedVersion(Int)
    /// Ключ комнаты имеет неверный размер или формат.
    case invalidKey
}

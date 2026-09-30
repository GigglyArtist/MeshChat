// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Расширяет `ChatSessionManaging` идентификатором сессии и QR-приглашением (§7.2).
protocol HostSessionManaging: ChatSessionManaging {

    /// Уникальный идентификатор текущей сессии (генерируется в `init`).
    nonisolated var sessionID: UUID { get }

    /// Приглашение для показа клиентам в виде QR-кода.
    nonisolated var invite: RoomInvite { get }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Фабрика сетевых сессий; создаётся один раз в `App/` (§7.2).
protocol MeshNetworking: Sendable {

    /// Создаёт и возвращает незапущенную хост-сессию.
    nonisolated func makeHostSession(
        identity: LocalIdentity,
        secret: any RoomSecret
    ) -> any HostSessionManaging

    /// Создаёт и возвращает незапущенную клиентскую сессию.
    nonisolated func makeClientSession(
        identity: LocalIdentity,
        invite: RoomInvite,
        secret: any RoomSecret
    ) -> any ChatSessionManaging
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Фабрика сетевых сессий; создаётся один раз в `App/` (§7.2).
///
/// Методы не помечены `nonisolated`: они создают акторы с `@MainActor`-изолированным
/// `init` (следствие `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) и поэтому сами должны
/// выполняться на `@MainActor`. Это исключение из правила «nonisolated на каждом требовании»
/// обусловлено ограничением языка: синхронный `init` актора нельзя пометить `nonisolated`.
protocol MeshNetworking: Sendable {

    /// Создаёт и возвращает незапущенную хост-сессию.
    func makeHostSession(
        identity: LocalIdentity,
        secret: any RoomSecret
    ) -> any HostSessionManaging

    /// Создаёт и возвращает незапущенную клиентскую сессию.
    func makeClientSession(
        identity: LocalIdentity,
        invite: RoomInvite,
        secret: any RoomSecret
    ) -> any ChatSessionManaging
}

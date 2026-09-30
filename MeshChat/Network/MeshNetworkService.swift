// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Фабрика сессий на основе реального Bonjour-транспорта (§7, §7.4).
///
/// Создаёт `HostSession` и `ClientSession` с настоящими `BonjourHostListener`
/// и `BonjourClientConnector`. Конкретизация `MeshNetworking` для production-окружения.
///
/// Методы выполняются на `@MainActor` (вывод проекта): см. комментарий к `MeshNetworking`.
struct MeshNetworkService: MeshNetworking {

    private let configuration: NetworkConfiguration

    init(configuration: NetworkConfiguration = .standard) {
        self.configuration = configuration
    }

    func makeHostSession(
        identity: LocalIdentity,
        secret: any RoomSecret
    ) -> any HostSessionManaging {
        HostSession(identity: identity, secret: secret,
                    listener: BonjourHostListener(configuration: configuration),
                    configuration: configuration)
    }

    func makeClientSession(
        identity: LocalIdentity,
        invite: RoomInvite,
        secret: any RoomSecret
    ) -> any ChatSessionManaging {
        ClientSession(identity: identity, invite: invite, secret: secret,
                      connector: BonjourClientConnector(configuration: configuration),
                      configuration: configuration)
    }
}

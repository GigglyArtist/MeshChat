// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Результат запуска приложения (§13).
/// Единственное место, где создаются конкретные реализации зависимостей.
enum AppStartup {
    case ready(AppEnvironment)
    case failed(String)

    /// Инициализирует все зависимости в правильном порядке.
    /// Любая ошибка приводит к `.failed` вместо падения приложения.
    @MainActor static func live() -> AppStartup {
        let service = (Bundle.main.bundleIdentifier ?? "com.meshchat") + ".identity"
        let keychain = KeychainStore(service: service)
        let identity = IdentityProvider(keychain: keychain)
        // Генерируем PermanentPeerID до появления UI, чтобы онбординг не падал при сохранении ника
        do {
            _ = try identity.permanentPeerID()
        } catch {
            return .failed("Не удалось получить идентификатор устройства: \(error.localizedDescription)")
        }
        let controller: PersistenceController
        do {
            controller = try PersistenceController()
        } catch {
            return .failed("Не удалось загрузить хранилище данных: \(error.localizedDescription)")
        }
        let storage = CoreDataStorageManager(controller: controller)
        let secrets = RoomCredentialsFactory()
        let rooms = RoomService(
            identity: identity,
            secrets: secrets,
            network: MeshNetworkService(),
            storage: storage
        )
        return .ready(AppEnvironment(identity: identity, storage: storage, secrets: secrets, rooms: rooms))
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Неизменяемый контейнер зависимостей приложения (§13).
/// Все поля — протоколы Domain, конкретные типы создаются только в `AppStartup`.
struct AppEnvironment: Sendable {
    let identity: any IdentityProviding
    let storage: any StorageManaging
    /// Фабрика активных комнат: создание и вход (§13, с этапа 7 `secrets` внутри RoomService).
    let rooms: any RoomServicing

    // MARK: - Previews

    #if DEBUG
    /// Среда для SwiftUI Previews: PreviewIdentityProvider + in-memory CoreData + PreviewRoomService.
    @MainActor static func preview(hasNickname: Bool = true) -> AppEnvironment {
        let identity = PreviewIdentityProvider(nickname: hasNickname ? "Preview User" : nil)
        let controller: PersistenceController
        do {
            controller = try PersistenceController(inMemory: true)
        } catch {
            fatalError("Preview: не удалось создать in-memory Core Data хранилище: \(error)")
        }
        let storage = CoreDataStorageManager(controller: controller)
        return AppEnvironment(
            identity: identity,
            storage: storage,
            rooms: PreviewRoomService()
        )
    }
    #endif
}

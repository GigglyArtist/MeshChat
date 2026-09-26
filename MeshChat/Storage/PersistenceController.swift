// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import CoreData

/// Обёртка над NSPersistentContainer. Создаёт стек Core Data и предоставляет контексты.
nonisolated final class PersistenceController {

    static let modelName = "MeshChat"

    /// Модель Core Data загружается один раз на весь процесс.
    /// Несколько экземпляров NSManagedObjectModel с одинаковыми сущностями ломают юнит-тесты
    /// («Multiple NSEntityDescriptions claim the same class»).
    /// nonisolated(unsafe) безопасен: static let инициализируется ровно один раз через dispatch_once.
    nonisolated(unsafe) static let model: NSManagedObjectModel = {
        guard let url = Bundle(for: PeerEntity.self).url(forResource: modelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            // Модель не найдена — ошибка сборки, а не пользователя.
            fatalError("Не найдена модель Core Data '\(modelName).momd' в бандле приложения")
        }
        return model
    }()

    let container: NSPersistentContainer

    /// Инициализирует стек Core Data.
    /// - Parameter inMemory: `true` — SQLite на `/dev/null` (для тестов и Previews);
    ///   поддерживает uniqueness constraints в отличие от NSInMemoryStoreType.
    nonisolated init(inMemory: Bool = false) throws {
        let container = NSPersistentContainer(
            name: Self.modelName,
            managedObjectModel: Self.model
        )
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let error = loadError {
            throw StorageError.storeLoadingFailed(error.localizedDescription)
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        self.container = container
    }

    /// Создаёт новый фоновый контекст для использования в CoreDataStorageManager.
    nonisolated func makeBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        ctx.name = "storage.background"
        return ctx
    }
}

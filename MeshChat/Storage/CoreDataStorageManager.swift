// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import CoreData

/// Реализует StorageManaging поверх одного фонового NSManagedObjectContext.
///
/// `@unchecked Sendable` безопасен: `controller` и `context` — неизменяемые `let`-свойства;
/// `context` используется исключительно через `context.perform`, что гарантирует сериализацию.
nonisolated final class CoreDataStorageManager: StorageManaging, @unchecked Sendable {

    private let controller: PersistenceController
    private let context: NSManagedObjectContext

    nonisolated init(controller: PersistenceController) {
        self.controller = controller
        self.context = controller.makeBackgroundContext()
    }

    // MARK: Sessions

    @discardableResult
    nonisolated func createSession(id: UUID, role: SessionRole, createdAt: Date) async throws -> ChatSessionInfo {
        try await context.perform {
            let request = NSFetchRequest<ChatSessionEntity>(entityName: ChatSessionEntity.entityName)
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            if let existing = try self.context.fetch(request).first {
                return existing.toDomain()
            }
            let entity = ChatSessionEntity(context: self.context)
            entity.id = id
            entity.roleRaw = role.rawValue
            entity.createdAt = createdAt
            try self.save()
            return entity.toDomain()
        }
    }

    nonisolated func endSession(id: UUID, endedAt: Date) async throws {
        try await context.perform {
            let entity = try self.fetchSession(id: id)
            entity.endedAt = endedAt
            try self.save()
        }
    }

    nonisolated func deleteSession(id: UUID) async throws {
        try await context.perform {
            let entity = try self.fetchSession(id: id)
            self.context.delete(entity)
            try self.save()
        }
    }

    nonisolated func session(id: UUID) async throws -> ChatSessionInfo? {
        try await context.perform {
            let request = NSFetchRequest<ChatSessionEntity>(entityName: ChatSessionEntity.entityName)
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            return try self.context.fetch(request).first?.toDomain()
        }
    }

    nonisolated func allSessions() async throws -> [ChatSessionInfo] {
        try await context.perform {
            let request = NSFetchRequest<ChatSessionEntity>(entityName: ChatSessionEntity.entityName)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            return try self.context.fetch(request).map { $0.toDomain() }
        }
    }

    // MARK: Peers

    @discardableResult
    nonisolated func upsertPeer(_ profile: PeerProfile, seenAt: Date) async throws -> PeerProfile {
        try await context.perform {
            let request = NSFetchRequest<PeerEntity>(entityName: PeerEntity.entityName)
            request.predicate = NSPredicate(format: "id == %@", profile.id as CVarArg)
            request.fetchLimit = 1
            let entity: PeerEntity
            if let existing = try self.context.fetch(request).first {
                existing.nickname = profile.nickname
                existing.lastSeenAt = seenAt
                entity = existing
            } else {
                let new = PeerEntity(context: self.context)
                new.id = profile.id
                new.nickname = profile.nickname
                new.lastSeenAt = seenAt
                entity = new
            }
            try self.save()
            return entity.toDomain()
        }
    }

    nonisolated func peer(id: UUID) async throws -> PeerProfile? {
        try await context.perform {
            let request = NSFetchRequest<PeerEntity>(entityName: PeerEntity.entityName)
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            return try self.context.fetch(request).first?.toDomain()
        }
    }

    nonisolated func allPeers() async throws -> [PeerProfile] {
        try await context.perform {
            let request = NSFetchRequest<PeerEntity>(entityName: PeerEntity.entityName)
            request.sortDescriptors = [NSSortDescriptor(key: "lastSeenAt", ascending: false)]
            return try self.context.fetch(request).map { $0.toDomain() }
        }
    }

    nonisolated func addParticipant(peerID: UUID, toSession sessionID: UUID) async throws {
        try await context.perform {
            let session = try self.fetchSession(id: sessionID)
            let peerRequest = NSFetchRequest<PeerEntity>(entityName: PeerEntity.entityName)
            peerRequest.predicate = NSPredicate(format: "id == %@", peerID as CVarArg)
            peerRequest.fetchLimit = 1
            guard let peer = try self.context.fetch(peerRequest).first else {
                throw StorageError.peerNotFound(peerID)
            }
            // Идемпотентно: если уже участник — пропускаем
            if session.participants.contains(peer) { return }
            session.participants.insert(peer)
            try self.save()
        }
    }

    nonisolated func sessions(withPeer peerID: UUID) async throws -> [ChatSessionInfo] {
        try await context.perform {
            let request = NSFetchRequest<ChatSessionEntity>(entityName: ChatSessionEntity.entityName)
            request.predicate = NSPredicate(format: "ANY participants.id == %@", peerID as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            return try self.context.fetch(request).map { $0.toDomain() }
        }
    }

    // MARK: Messages

    nonisolated func saveMessage(_ message: ChatMessage, inSession sessionID: UUID) async throws {
        try await context.perform {
            let session = try self.fetchSession(id: sessionID)
            // Идемпотентно по message.id
            let existingRequest = NSFetchRequest<MessageEntity>(entityName: MessageEntity.entityName)
            existingRequest.predicate = NSPredicate(format: "id == %@", message.id as CVarArg)
            existingRequest.fetchLimit = 1
            if try self.context.fetch(existingRequest).first != nil { return }
            let entity = MessageEntity(context: self.context)
            entity.id = message.id
            entity.text = message.text
            entity.timestamp = message.timestamp
            entity.senderID = message.senderID
            entity.session = session
            try self.save()
        }
    }

    nonisolated func messages(inSession sessionID: UUID) async throws -> [ChatMessage] {
        try await context.perform {
            let sessionRequest = NSFetchRequest<ChatSessionEntity>(entityName: ChatSessionEntity.entityName)
            sessionRequest.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
            sessionRequest.fetchLimit = 1
            guard try self.context.fetch(sessionRequest).first != nil else {
                throw StorageError.sessionNotFound(sessionID)
            }
            let request = NSFetchRequest<MessageEntity>(entityName: MessageEntity.entityName)
            request.predicate = NSPredicate(format: "session.id == %@", sessionID as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            return try self.context.fetch(request).map { $0.toDomain() }
        }
    }

    // MARK: Private helpers

    private func fetchSession(id: UUID) throws -> ChatSessionEntity {
        let request = NSFetchRequest<ChatSessionEntity>(entityName: ChatSessionEntity.entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let entity = try context.fetch(request).first else {
            throw StorageError.sessionNotFound(id)
        }
        return entity
    }

    private func save() throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw StorageError.saveFailed(error.localizedDescription)
        }
    }
}

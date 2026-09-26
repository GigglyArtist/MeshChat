// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

@Suite("CoreDataStorageManager", .serialized)
struct CoreDataStorageManagerTests {

    private func makeManager() throws -> CoreDataStorageManager {
        let controller = try PersistenceController(inMemory: true)
        return CoreDataStorageManager(controller: controller)
    }

    // MARK: Sessions

    @Test("Созданная сессия находится по id; повторный createSession не создаёт дубль")
    func createSessionIdempotent() async throws {
        let manager = try makeManager()
        let id = UUID()
        let date = Date()

        let first = try await manager.createSession(id: id, role: .host, createdAt: date)
        let second = try await manager.createSession(id: id, role: .host, createdAt: date)

        #expect(first.id == id)
        #expect(second.id == id)

        let all = try await manager.allSessions()
        #expect(all.count == 1)

        let found = try await manager.session(id: id)
        #expect(found?.id == id)
    }

    // MARK: Peers

    @Test("Новый upsertPeer создаёт собеседника; повторный с тем же id обновляет ник")
    func upsertPeerIdempotent() async throws {
        let manager = try makeManager()
        let id = UUID()
        let original = PeerProfile(id: id, nickname: "Alice")
        let updated = PeerProfile(id: id, nickname: "Alicia")

        try await manager.upsertPeer(original, seenAt: Date())
        try await manager.upsertPeer(updated, seenAt: Date())

        let peers = try await manager.allPeers()
        #expect(peers.count == 1)
        #expect(peers[0].nickname == "Alicia")
    }

    // MARK: История с другом (R14)

    @Test("История с другом: sessions(withPeer:) возвращает сессии по убыванию createdAt")
    func historyWithFriend() async throws {
        let manager = try makeManager()
        let peerID = UUID()
        try await manager.upsertPeer(PeerProfile(id: peerID, nickname: "Friend"), seenAt: Date())

        let now = Date()
        let idA = UUID()
        let idB = UUID()
        try await manager.createSession(id: idA, role: .client, createdAt: now.addingTimeInterval(-100))
        try await manager.createSession(id: idB, role: .client, createdAt: now.addingTimeInterval(-50))
        try await manager.addParticipant(peerID: peerID, toSession: idA)
        try await manager.addParticipant(peerID: peerID, toSession: idB)

        let sessions = try await manager.sessions(withPeer: peerID)
        #expect(sessions.count == 2)
        #expect(sessions[0].id == idB) // новее сверху
        #expect(sessions[1].id == idA)
    }

    // MARK: addParticipant

    @Test("Двойной addParticipant оставляет одного участника в сессии")
    func addParticipantIdempotent() async throws {
        let manager = try makeManager()
        let sessionID = UUID()
        let peerID = UUID()
        try await manager.createSession(id: sessionID, role: .host, createdAt: Date())
        try await manager.upsertPeer(PeerProfile(id: peerID, nickname: "Bob"), seenAt: Date())

        try await manager.addParticipant(peerID: peerID, toSession: sessionID)
        try await manager.addParticipant(peerID: peerID, toSession: sessionID)

        let session = try await manager.session(id: sessionID)
        #expect(session?.participants.count == 1)
    }

    // MARK: Messages

    @Test("Сообщения возвращаются в порядке возрастания timestamp независимо от порядка сохранения")
    func messagesOrderedByTimestamp() async throws {
        let manager = try makeManager()
        let sessionID = UUID()
        try await manager.createSession(id: sessionID, role: .host, createdAt: Date())

        let now = Date()
        let m1 = ChatMessage(id: UUID(), text: "first", timestamp: now.addingTimeInterval(-2), senderID: UUID())
        let m2 = ChatMessage(id: UUID(), text: "second", timestamp: now.addingTimeInterval(-1), senderID: UUID())
        let m3 = ChatMessage(id: UUID(), text: "third", timestamp: now, senderID: UUID())

        // Сохраняем не по порядку
        try await manager.saveMessage(m3, inSession: sessionID)
        try await manager.saveMessage(m1, inSession: sessionID)
        try await manager.saveMessage(m2, inSession: sessionID)

        let messages = try await manager.messages(inSession: sessionID)
        #expect(messages.map(\.text) == ["first", "second", "third"])
    }

    @Test("Повторный saveMessage с тем же id не создаёт дубль")
    func saveMessageIdempotent() async throws {
        let manager = try makeManager()
        let sessionID = UUID()
        try await manager.createSession(id: sessionID, role: .host, createdAt: Date())

        let msg = ChatMessage(id: UUID(), text: "hello", timestamp: Date(), senderID: UUID())
        try await manager.saveMessage(msg, inSession: sessionID)
        try await manager.saveMessage(msg, inSession: sessionID)

        let messages = try await manager.messages(inSession: sessionID)
        #expect(messages.count == 1)
    }

    // MARK: Каскад (R13)

    @Test("deleteSession каскадно удаляет сообщения, но не удаляет Peer")
    func deleteSessionCascade() async throws {
        let manager = try makeManager()
        let sessionID = UUID()
        let peerID = UUID()
        try await manager.createSession(id: sessionID, role: .host, createdAt: Date())
        try await manager.upsertPeer(PeerProfile(id: peerID, nickname: "Carol"), seenAt: Date())
        try await manager.addParticipant(peerID: peerID, toSession: sessionID)

        let msg = ChatMessage(id: UUID(), text: "test", timestamp: Date(), senderID: peerID)
        try await manager.saveMessage(msg, inSession: sessionID)

        try await manager.deleteSession(id: sessionID)

        // Сессия удалена
        let found = try await manager.session(id: sessionID)
        #expect(found == nil)

        // Сообщения недоступны — сессия не найдена
        await #expect(throws: StorageError.sessionNotFound(sessionID)) {
            _ = try await manager.messages(inSession: sessionID)
        }

        // Peer сохранился
        let peer = try await manager.peer(id: peerID)
        #expect(peer?.id == peerID)
    }

    @Test("saveMessage в несуществующую сессию бросает sessionNotFound")
    func saveMessageMissingSession() async throws {
        let manager = try makeManager()
        let fakeSessionID = UUID()
        let msg = ChatMessage(id: UUID(), text: "ghost", timestamp: Date(), senderID: UUID())

        await #expect(throws: StorageError.sessionNotFound(fakeSessionID)) {
            try await manager.saveMessage(msg, inSession: fakeSessionID)
        }
    }

    // MARK: endSession

    @Test("endSession проставляет endedAt")
    func endSessionSetsDate() async throws {
        let manager = try makeManager()
        let sessionID = UUID()
        try await manager.createSession(id: sessionID, role: .client, createdAt: Date())

        let endDate = Date()
        try await manager.endSession(id: sessionID, endedAt: endDate)

        let session = try await manager.session(id: sessionID)
        #expect(session?.endedAt != nil)
    }

    // MARK: allPeers

    @Test("allPeers() возвращает собеседников по убыванию lastSeenAt")
    func allPeersSortedByLastSeen() async throws {
        let manager = try makeManager()
        let now = Date()
        let p1 = PeerProfile(id: UUID(), nickname: "Alice")
        let p2 = PeerProfile(id: UUID(), nickname: "Bob")

        try await manager.upsertPeer(p1, seenAt: now.addingTimeInterval(-100))
        try await manager.upsertPeer(p2, seenAt: now)

        let peers = try await manager.allPeers()
        #expect(peers.count == 2)
        #expect(peers[0].id == p2.id) // более свежий сверху
        #expect(peers[1].id == p1.id)
    }
}

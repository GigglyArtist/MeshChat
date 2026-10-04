// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

/// `@MainActor` нужен: `PersistenceController.init` выводится как `@MainActor`-изолированный
/// при `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@MainActor
@Suite("HistoryService", .serialized, .timeLimit(.minutes(1)))
struct HistoryServiceTests {

    func makeStorage() throws -> CoreDataStorageManager {
        let controller = try PersistenceController(inMemory: true)
        return CoreDataStorageManager(controller: controller)
    }

    // MARK: 1. Пустое хранилище

    @Test("empty storage returns empty peer summaries")
    func emptyStorageReturnsEmpty() async throws {
        let storage = try makeStorage()
        let service = HistoryService(storage: storage)
        let summaries = try await service.peerSummaries()
        #expect(summaries.isEmpty)
    }

    // MARK: 2. Порядок и счётчики

    @Test("peer summaries sorted by last session desc, no-session peers sorted by name")
    func peerSummaryOrderAndCounts() async throws {
        let storage = try makeStorage()
        let service = HistoryService(storage: storage)

        let peerA = PeerProfile(id: UUID(), nickname: "A")
        let peerB = PeerProfile(id: UUID(), nickname: "B")
        let peerC = PeerProfile(id: UUID(), nickname: "C")

        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 200)
        let t3 = Date(timeIntervalSince1970: 300) // t3 > t2

        try await storage.upsertPeer(peerA, seenAt: t1)
        try await storage.upsertPeer(peerB, seenAt: t3)
        try await storage.upsertPeer(peerC, seenAt: t1)

        // A — 2 сессии (t1, t2)
        let sA1 = try await storage.createSession(id: UUID(), role: .host, createdAt: t1)
        let sA2 = try await storage.createSession(id: UUID(), role: .host, createdAt: t2)
        try await storage.addParticipant(peerID: peerA.id, toSession: sA1.id)
        try await storage.addParticipant(peerID: peerA.id, toSession: sA2.id)

        // B — 1 сессия (t3)
        let sB1 = try await storage.createSession(id: UUID(), role: .client, createdAt: t3)
        try await storage.addParticipant(peerID: peerB.id, toSession: sB1.id)

        // C — 0 сессий

        let summaries = try await service.peerSummaries()

        #expect(summaries.count == 3)
        // Ожидаем: B (t3), A (t2), C (нет сессий)
        #expect(summaries[0].profile.id == peerB.id)
        #expect(summaries[1].profile.id == peerA.id)
        #expect(summaries[2].profile.id == peerC.id)
        // Счётчики
        #expect(summaries[0].sessionCount == 1)
        #expect(summaries[1].sessionCount == 2)
        #expect(summaries[2].sessionCount == 0)
        // lastSessionAt
        #expect(summaries[0].lastSessionAt == t3)
        #expect(summaries[1].lastSessionAt == t2)
        #expect(summaries[2].lastSessionAt == nil)
    }

    // MARK: 3. Двое без сессий — алфавитный порядок

    @Test("peers without sessions are sorted alphabetically")
    func peersWithoutSessionsSortedAlphabetically() async throws {
        let storage = try makeStorage()
        let service = HistoryService(storage: storage)

        let vova = PeerProfile(id: UUID(), nickname: "Вова")
        let anya = PeerProfile(id: UUID(), nickname: "Аня")
        try await storage.upsertPeer(vova, seenAt: Date())
        try await storage.upsertPeer(anya, seenAt: Date())

        let summaries = try await service.peerSummaries()

        #expect(summaries.count == 2)
        #expect(summaries[0].profile.nickname == "Аня")
        #expect(summaries[1].profile.nickname == "Вова")
    }

    // MARK: 4. sessions(withPeer:) — новые сверху

    @Test("sessions(withPeer:) returns sessions newest first")
    func sessionsWithPeerNewestFirst() async throws {
        let storage = try makeStorage()
        let service = HistoryService(storage: storage)

        let peer = PeerProfile(id: UUID(), nickname: "Alice")
        try await storage.upsertPeer(peer, seenAt: Date())

        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 200)
        let t3 = Date(timeIntervalSince1970: 300)

        let s1 = try await storage.createSession(id: UUID(), role: .host, createdAt: t1)
        let s2 = try await storage.createSession(id: UUID(), role: .client, createdAt: t2)
        let s3 = try await storage.createSession(id: UUID(), role: .host, createdAt: t3)
        try await storage.addParticipant(peerID: peer.id, toSession: s1.id)
        try await storage.addParticipant(peerID: peer.id, toSession: s2.id)
        try await storage.addParticipant(peerID: peer.id, toSession: s3.id)

        let sessions = try await service.sessions(withPeer: peer.id)

        #expect(sessions.count == 3)
        #expect(sessions[0].id == s3.id)
        #expect(sessions[1].id == s2.id)
        #expect(sessions[2].id == s1.id)
    }

    // MARK: 5. transcript — сообщения по возрастанию timestamp, участники верные

    @Test("transcript returns messages ascending and includes participants")
    func transcriptMessagesAscendingAndParticipants() async throws {
        let storage = try makeStorage()
        let service = HistoryService(storage: storage)

        let peer = PeerProfile(id: UUID(), nickname: "Bob")
        try await storage.upsertPeer(peer, seenAt: Date())

        let sessionID = UUID()
        try await storage.createSession(id: sessionID, role: .host, createdAt: Date())
        try await storage.addParticipant(peerID: peer.id, toSession: sessionID)

        let t1 = Date(timeIntervalSince1970: 100).flooredToMilliseconds
        let t2 = Date(timeIntervalSince1970: 200).flooredToMilliseconds
        let t3 = Date(timeIntervalSince1970: 300).flooredToMilliseconds

        let msg1 = ChatMessage(id: UUID(), text: "first", timestamp: t1, senderID: peer.id)
        let msg2 = ChatMessage(id: UUID(), text: "second", timestamp: t2, senderID: UUID())
        let msg3 = ChatMessage(id: UUID(), text: "third", timestamp: t3, senderID: peer.id)

        // Сохраняем не по порядку; хранилище сортирует по timestamp
        try await storage.saveMessage(msg3, inSession: sessionID)
        try await storage.saveMessage(msg1, inSession: sessionID)
        try await storage.saveMessage(msg2, inSession: sessionID)

        let transcript = try await service.transcript(sessionID: sessionID)

        #expect(transcript.session.id == sessionID)
        #expect(transcript.session.participants.contains { $0.id == peer.id })
        #expect(transcript.messages.count == 3)
        #expect(transcript.messages[0].id == msg1.id)
        #expect(transcript.messages[1].id == msg2.id)
        #expect(transcript.messages[2].id == msg3.id)
    }

    // MARK: 6. transcript неизвестной сессии → sessionNotFound

    @Test("transcript for unknown session throws sessionNotFound")
    func transcriptUnknownSessionThrows() async throws {
        let storage = try makeStorage()
        let service = HistoryService(storage: storage)

        let unknownID = UUID()
        await #expect(throws: StorageError.sessionNotFound(unknownID)) {
            try await service.transcript(sessionID: unknownID)
        }
    }

    // MARK: 7. Удаление (R13)

    @Test("deleteSession removes session/messages but keeps peer")
    func deleteSessionKeepsPeer() async throws {
        let storage = try makeStorage()
        let service = HistoryService(storage: storage)

        let peer = PeerProfile(id: UUID(), nickname: "Charlie")
        try await storage.upsertPeer(peer, seenAt: Date())

        let sessionID = UUID()
        try await storage.createSession(id: sessionID, role: .host, createdAt: Date())
        try await storage.addParticipant(peerID: peer.id, toSession: sessionID)

        let msg = ChatMessage(id: UUID(), text: "hello",
                              timestamp: Date().flooredToMilliseconds, senderID: peer.id)
        try await storage.saveMessage(msg, inSession: sessionID)

        // Сессия существует
        let before = try await service.sessions(withPeer: peer.id)
        #expect(before.count == 1)

        try await service.deleteSession(id: sessionID)

        // transcript бросает sessionNotFound
        await #expect(throws: StorageError.sessionNotFound(sessionID)) {
            try await service.transcript(sessionID: sessionID)
        }
        // sessionCount уменьшился
        let summaries = try await service.peerSummaries()
        let peerSummary = try #require(summaries.first { $0.profile.id == peer.id })
        #expect(peerSummary.sessionCount == 0)
        // Собеседник остался
        #expect(summaries.contains { $0.profile.id == peer.id })
    }
}

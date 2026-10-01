// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

/// `@MainActor` нужен: `ActiveRoom.init` выводится как `@MainActor`-изолированный
/// при `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@MainActor
@Suite("ActiveRoom", .serialized, .timeLimit(.minutes(1)))
struct ActiveRoomTests {

    // MARK: - Вспомогательные методы

    private let sessionID = UUID()
    private let localID = UUID()

    func makeStorage() throws -> CoreDataStorageManager {
        let controller = try PersistenceController(inMemory: true)
        return CoreDataStorageManager(controller: controller)
    }

    func makeRoom(
        role: SessionRole = .host,
        sessionID: UUID? = nil,
        storage: any StorageManaging
    ) -> (ActiveRoom, FakeChatSession) {
        let session = FakeChatSession(role: role, senderID: localID)
        let room = ActiveRoom(
            session: session,
            storage: storage,
            localPeerID: localID,
            invite: nil,
            sessionID: sessionID
        )
        return (room, session)
    }

    // MARK: 1. participantJoined → participantsChanged + notice(.joined) + peer saved

    @Test("participantJoined emits participantsChanged and notice(.joined), saves peer")
    func participantJoinedEmitsEvents() async throws {
        let storage = try makeStorage()
        let (room, session) = makeRoom(sessionID: sessionID, storage: storage)
        let probe = EventProbe<RoomEvent>(stream: room.events)
        await room.start()

        let alice = PeerProfile(id: UUID(), nickname: "Alice")
        session.emit(.participantJoined(alice))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .participantsChanged(let ps) = $0 { return ps.contains { $0.id == alice.id } }
            return false
        }
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .notice(.joined(let name)) = $0 { return name == "Alice" }; return false
        }
        // Storage was updated before events were emitted (sequential loop)
        let peers = try await storage.allPeers()
        #expect(peers.contains { $0.id == alice.id })
    }

    // MARK: 2. participantLeft → participantsChanged + notice(.left)

    @Test("participantLeft removes peer from list and emits notice(.left)")
    func participantLeftEmitsEvents() async throws {
        let storage = try makeStorage()
        let (room, session) = makeRoom(sessionID: sessionID, storage: storage)
        let probe = EventProbe<RoomEvent>(stream: room.events)
        await room.start()

        let bob = PeerProfile(id: UUID(), nickname: "Bob")
        session.emit(.participantJoined(bob))
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .participantsChanged = $0 { return true }; return false
        }

        session.emit(.participantLeft(bob, .left))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .participantsChanged(let ps) = $0 { return !ps.contains { $0.id == bob.id } }
            return false
        }
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .notice(.left(let name, let r)) = $0 { return name == "Bob" && r == .left }
            return false
        }
    }

    // MARK: 3. messageReceived → messageAppended + saved in storage

    @Test("messageReceived emits messageAppended and saves message to storage")
    func messageReceivedSavesAndEmits() async throws {
        let storage = try makeStorage()
        try await storage.createSession(id: sessionID, role: .host, createdAt: Date())
        let (room, session) = makeRoom(sessionID: sessionID, storage: storage)
        let probe = EventProbe<RoomEvent>(stream: room.events)
        await room.start()

        let msgID = UUID()
        let msg = ChatMessage(id: msgID, text: "hello",
                              timestamp: Date().flooredToMilliseconds, senderID: UUID())
        session.emit(.messageReceived(msg))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .messageAppended(let m) = $0 { return m.id == msgID }; return false
        }
        let stored = try await storage.messages(inSession: sessionID)
        #expect(stored.contains { $0.id == msgID })
    }

    // MARK: 4. stateChanged(.ended) → stateChanged emitted + stream ends + endSession called

    @Test("stateChanged(.ended) emits stateChanged, ends stream, calls endSession")
    func stateChangedEndedClosesStream() async throws {
        let storage = try makeStorage()
        try await storage.createSession(id: sessionID, role: .host, createdAt: Date())
        let (room, session) = makeRoom(sessionID: sessionID, storage: storage)
        let probe = EventProbe<RoomEvent>(stream: room.events)
        await room.start()

        session.emit(.stateChanged(.ended(.hostEnded)))
        session.finish()

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.hostEnded)) = $0 { return true }; return false
        }
        try await probe.waitForFinish(timeout: .seconds(5))

        // endSession was called before stateChanged was emitted (sequential loop)
        let info = try await storage.session(id: sessionID)
        #expect(info?.endedAt != nil)
    }

    // MARK: 5. established (client) → createSession in storage

    @Test("established event creates client session in storage")
    func establishedCreatesSession() async throws {
        let storage = try makeStorage()
        let (room, session) = makeRoom(role: .client, sessionID: nil, storage: storage)
        let probe = EventProbe<RoomEvent>(stream: room.events)
        await room.start()

        let newSID = UUID()
        let host = PeerProfile(id: UUID(), nickname: "Host")
        // Sequential: participantJoined is handled only after established completes.
        // When participantsChanged arrives, createSession has already run.
        session.emit(.established(sessionID: newSID))
        session.emit(.participantJoined(host))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .participantsChanged = $0 { return true }; return false
        }
        let info = try await storage.session(id: newSID)
        #expect(info?.id == newSID)
        #expect(info?.role == .client)
    }

    // MARK: 6. send(text:) → messageAppended + saved in storage

    @Test("send emits messageAppended and saves outgoing message to storage")
    func sendEmitsAndSaves() async throws {
        let storage = try makeStorage()
        try await storage.createSession(id: sessionID, role: .host, createdAt: Date())
        let (room, session) = makeRoom(sessionID: sessionID, storage: storage)
        let probe = EventProbe<RoomEvent>(stream: room.events)
        await room.start()
        _ = session

        try await room.send(text: "test message")

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .messageAppended(let m) = $0 { return m.text == "test message" }; return false
        }
        let stored = try await storage.messages(inSession: sessionID)
        #expect(stored.contains { $0.text == "test message" })
    }

    // MARK: 7. Storage error doesn't break the chat

    @Test("storage error on participantJoined still emits RoomEvent (§11.1)")
    func storageErrorDoesNotBreakChat() async throws {
        let (room, session) = makeRoom(sessionID: sessionID, storage: FailingStorage())
        let probe = EventProbe<RoomEvent>(stream: room.events)
        await room.start()

        let charlie = PeerProfile(id: UUID(), nickname: "Charlie")
        session.emit(.participantJoined(charlie))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .notice(.joined(let name)) = $0 { return name == "Charlie" }; return false
        }
    }

    // MARK: 8. start() is idempotent

    @Test("calling start() twice does not create duplicate event loops")
    func startIsIdempotent() async throws {
        let storage = try makeStorage()
        let (room, session) = makeRoom(sessionID: sessionID, storage: storage)
        let probe = EventProbe<RoomEvent>(stream: room.events)
        await room.start()
        await room.start()  // second call must be a no-op

        let alice = PeerProfile(id: UUID(), nickname: "Alice")
        session.emit(.participantJoined(alice))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .participantsChanged = $0 { return true }; return false
        }
        // Allow any spurious duplicates to arrive
        try await Task.sleep(for: .milliseconds(100))
        let changes = probe.events.filter {
            if case .participantsChanged = $0 { return true }; return false
        }
        #expect(changes.count == 1, "second start() must not create a second event loop")
    }
}

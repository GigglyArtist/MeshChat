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

    // MARK: N. appDidBecomeActive → session.resumeAfterForeground()

    @Test("appDidBecomeActive() forwards to session.resumeAfterForeground()")
    func appDidBecomeActiveForwardsToSession() async throws {
        let storage = try makeStorage()
        let (room, session) = makeRoom(storage: storage)
        await room.start()

        await room.appDidBecomeActive()
        #expect(session.resumeAfterForegroundCount == 1)
    }

    // MARK: 9. established с историей → messagesRestored до participantsChanged

    @Test("established with pre-existing messages emits messagesRestored before participantsChanged")
    func rejoinEmitsMessagesRestored() async throws {
        let storage = try makeStorage()
        let sid = UUID()
        let peerID = UUID()
        let peer = PeerProfile(id: peerID, nickname: "Alice")

        // Подготовить сессию и участника в хранилище
        try await storage.createSession(id: sid, role: .client, createdAt: Date())
        try await storage.upsertPeer(peer, seenAt: Date())
        try await storage.addParticipant(peerID: peerID, toSession: sid)

        let t1 = Date(timeIntervalSince1970: 100).flooredToMilliseconds
        let t2 = Date(timeIntervalSince1970: 200).flooredToMilliseconds
        let m1 = ChatMessage(id: UUID(), text: "first",  timestamp: t1, senderID: peerID)
        let m2 = ChatMessage(id: UUID(), text: "second", timestamp: t2, senderID: localID)
        try await storage.saveMessage(m1, inSession: sid)
        try await storage.saveMessage(m2, inSession: sid)

        let session = FakeChatSession(role: .client, senderID: localID)
        let room = ActiveRoom(session: session, storage: storage,
                              localPeerID: localID, invite: nil, sessionID: nil)
        let probe = EventProbe<RoomEvent>(stream: room.events)
        await room.start()

        let host = PeerProfile(id: UUID(), nickname: "Host")
        session.emit(.established(sessionID: sid))
        session.emit(.participantJoined(host))

        // Ждём participantsChanged, чтобы убедиться: established полностью обработан
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .participantsChanged = $0 { return true }; return false
        }

        // messagesRestored должен быть первым событием
        guard !probe.events.isEmpty else {
            Issue.record("probe.events is empty"); return
        }
        if case .messagesRestored(let messages, let knownPeers) = probe.events[0] {
            #expect(messages.count == 2)
            #expect(messages[0].text == "first")
            #expect(messages[1].text == "second")
            #expect(knownPeers.contains { $0.id == peerID })
        } else {
            Issue.record("Expected .messagesRestored as first event, got \(probe.events[0])")
        }
    }

    // MARK: 10. Новая сессия — messagesRestored не выдаётся

    @Test("established with no pre-existing messages does not emit messagesRestored")
    func newSessionNoMessagesRestored() async throws {
        let storage = try makeStorage()
        let (room, session) = makeRoom(role: .client, sessionID: nil, storage: storage)
        let probe = EventProbe<RoomEvent>(stream: room.events)
        await room.start()

        let sid = UUID()
        let host = PeerProfile(id: UUID(), nickname: "Host")
        session.emit(.established(sessionID: sid))
        session.emit(.participantJoined(host))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .participantsChanged = $0 { return true }; return false
        }

        // Небольшая пауза, чтобы дать шанс любому лишнему событию появиться
        try await Task.sleep(for: .milliseconds(200))

        let restored = probe.events.filter {
            if case .messagesRestored = $0 { return true }; return false
        }
        #expect(restored.isEmpty, "no messagesRestored expected for a fresh session")
    }

    // MARK: 11. Ошибка хранилища при загрузке сообщений — чат продолжает работу

    @Test("storage error on messages load does not break chat")
    func storageErrorOnMessagesDoesNotBreakChat() async throws {
        let session = FakeChatSession(role: .client, senderID: localID)
        // FailingStorage: createSession бросает, messages возвращает []
        let room = ActiveRoom(session: session, storage: FailingStorage(),
                              localPeerID: localID, invite: nil, sessionID: nil)
        let probe = EventProbe<RoomEvent>(stream: room.events)
        await room.start()

        let host = PeerProfile(id: UUID(), nickname: "Host")
        session.emit(.established(sessionID: UUID()))
        session.emit(.participantJoined(host))

        // participantsChanged должен дойти несмотря на ошибки хранилища
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .participantsChanged = $0 { return true }; return false
        }

        let restored = probe.events.filter {
            if case .messagesRestored = $0 { return true }; return false
        }
        #expect(restored.isEmpty, "FailingStorage.messages returns [] so no restore expected")
    }
}

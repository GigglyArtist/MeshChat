// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

/// Сквозные тесты Application-слоя: два `ActiveRoom` через общее хранилище.
///
/// `@MainActor` нужен: `ActiveRoom.init` выводится как `@MainActor`-изолированный
/// при `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@MainActor
@Suite("RoomLoopbackTests", .serialized, .timeLimit(.minutes(2)))
struct RoomLoopbackTests {

    // MARK: - Вспомогательные методы

    func makeStorage() throws -> CoreDataStorageManager {
        let controller = try PersistenceController(inMemory: true)
        return CoreDataStorageManager(controller: controller)
    }

    func makeRoom(
        session: FakeChatSession,
        storage: any StorageManaging,
        sessionID: UUID? = nil
    ) -> (ActiveRoom, EventProbe<RoomEvent>) {
        let room = ActiveRoom(session: session, storage: storage,
                              localPeerID: UUID(), invite: nil, sessionID: sessionID)
        let probe = EventProbe<RoomEvent>(stream: room.events)
        return (room, probe)
    }

    func makeSecret(byte: UInt8 = 0xAB) throws -> any RoomSecret {
        try RoomCredentials(roomKeyData: Data(repeating: byte, count: 32))
    }

    // MARK: 1. «Две комнаты — одна история» (R14)

    @Test("same peer in two consecutive sessions appears in shared history (R14)")
    func twoRoomsOneHistory() async throws {
        let storage = try makeStorage()
        let peerID = UUID()
        let peer = PeerProfile(id: peerID, nickname: "Alice")
        let hostSID = UUID()

        // --- Комната 1 (хост): Алиса присоединяется ---
        try await storage.createSession(id: hostSID, role: .host, createdAt: Date())
        let hostSession = FakeChatSession(role: .host)
        let (hostRoom, hostProbe) = makeRoom(session: hostSession, storage: storage,
                                             sessionID: hostSID)
        await hostRoom.start()
        hostSession.emit(.participantJoined(peer))
        _ = try await hostProbe.waitFor(timeout: .seconds(5)) {
            if case .notice(.joined) = $0 { return true }; return false
        }
        // Завершаем комнату 1
        hostSession.emit(.stateChanged(.ended(.leftByUser)))
        hostSession.finish()
        try await hostProbe.waitForFinish(timeout: .seconds(5))

        // --- Комната 2 (клиент): та же Алиса участвует ---
        let clientSID = UUID()
        let clientSession = FakeChatSession(role: .client)
        let (clientRoom, clientProbe) = makeRoom(session: clientSession, storage: storage)
        await clientRoom.start()

        // established → createSession; participantJoined → addParticipant к clientSID
        clientSession.emit(.established(sessionID: clientSID))
        clientSession.emit(.participantJoined(PeerProfile(id: UUID(), nickname: "Host")))
        clientSession.emit(.participantJoined(peer))   // та же Alice

        // Ждём два события notice(.joined) (Host + Alice)
        _ = try await clientProbe.waitFor(count: 2, timeout: .seconds(5)) {
            if case .notice(.joined) = $0 { return true }; return false
        }

        // История Алисы охватывает обе сессии
        let sessions = try await storage.sessions(withPeer: peerID)
        #expect(sessions.count == 2, "Alice should appear in both session records")
        let ids = Set(sessions.map(\.id))
        #expect(ids.contains(hostSID),   "host session missing from history")
        #expect(ids.contains(clientSID), "client session missing from history")
    }

    // MARK: 2. Отправка и приём в одной комнате — оба сообщения сохраняются

    @Test("outgoing and incoming messages both persisted in the same session")
    func sendAndReceivePersistedTogether() async throws {
        let storage = try makeStorage()
        let sessionID = UUID()
        let localID = UUID()
        try await storage.createSession(id: sessionID, role: .host, createdAt: Date())

        let session = FakeChatSession(role: .host, senderID: localID)
        let (room, probe) = makeRoom(session: session, storage: storage, sessionID: sessionID)
        await room.start()

        // Отправляем собственное сообщение
        try await room.send(text: "Привет от хоста")

        // Получаем входящее сообщение
        let incomingID = UUID()
        let incoming = ChatMessage(id: incomingID, text: "Привет от клиента",
                                   timestamp: Date().flooredToMilliseconds,
                                   senderID: UUID())
        session.emit(.messageReceived(incoming))

        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .messageAppended(let m) = $0 { return m.text == "Привет от хоста" }
            return false
        }
        _ = try await probe.waitFor(timeout: .seconds(5)) {
            if case .messageAppended(let m) = $0 { return m.id == incomingID }
            return false
        }

        let stored = try await storage.messages(inSession: sessionID)
        #expect(stored.count == 2, "both outgoing and incoming messages must be saved")
        #expect(stored.contains { $0.text == "Привет от хоста" })
        #expect(stored.contains { $0.id == incomingID })
    }

    // MARK: 3. Клиент переподключается и получает сохранённые сообщения (ADR-12)

    /// Клиент входит, отправляет «До обрыва», уходит, снова входит с тем же приглашением.
    /// Ожидаемый результат: первое событие нового `ActiveRoom` — `.messagesRestored` с
    /// сообщением «До обрыва», хост снова видит клиента, в хранилище ровно одна сессия с хостом.
    @Test("client rejoins and receives previously saved messages over real TLS (ADR-12)")
    func rejoinReceivesRestoredMessages() async throws {
        let storage = try makeStorage()
        let secret = try makeSecret()
        let hostIdentity = LocalIdentity.makeTest(nickname: "Host")
        let clientIdentity = LocalIdentity.makeTest(nickname: "Client")

        // Запустить хоста
        let tap = ListenerTap()
        let hostSession = HostSession(
            identity: hostIdentity, secret: secret,
            listener: tap, configuration: .loopback
        )
        try await storage.createSession(id: hostSession.sessionID, role: .host, createdAt: Date())
        let hostRoom = ActiveRoom(
            session: hostSession, storage: storage,
            localPeerID: hostIdentity.peerID, invite: hostSession.invite,
            sessionID: hostSession.sessionID
        )
        let hostProbe = EventProbe<RoomEvent>(stream: hostRoom.events)
        Task { await hostSession.start() }
        await hostRoom.start()

        _ = try await hostProbe.waitFor(timeout: .seconds(10)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }
        let port = try await tap.waitForPort()
        let invite = hostSession.invite
        let clientSecret = try RoomCredentials(roomKeyData: invite.roomKey)

        // Первое подключение клиента
        let session1 = ClientSession(
            identity: clientIdentity, invite: invite, secret: clientSecret,
            connector: LoopbackClientConnector(port: port), configuration: .loopback
        )
        let room1 = ActiveRoom(
            session: session1, storage: storage,
            localPeerID: clientIdentity.peerID, invite: invite, sessionID: nil
        )
        let probe1 = EventProbe<RoomEvent>(stream: room1.events)
        Task { await session1.start() }
        await room1.start()

        _ = try await probe1.waitFor(timeout: .seconds(10)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Клиент отправляет сообщение
        try await room1.send(text: "До обрыва")
        _ = try await probe1.waitFor(timeout: .seconds(5)) {
            if case .messageAppended(let m) = $0 { return m.text == "До обрыва" }; return false
        }

        // Клиент уходит
        await room1.leave()
        _ = try await hostProbe.waitFor(timeout: .seconds(5)) {
            if case .notice(.left) = $0 { return true }; return false
        }

        // Второе подключение (повторный вход) с тем же приглашением и тем же clientIdentity
        let session2 = ClientSession(
            identity: clientIdentity, invite: invite, secret: clientSecret,
            connector: LoopbackClientConnector(port: port), configuration: .loopback
        )
        let room2 = ActiveRoom(
            session: session2, storage: storage,
            localPeerID: clientIdentity.peerID, invite: invite, sessionID: nil
        )
        let probe2 = EventProbe<RoomEvent>(stream: room2.events)
        Task { await session2.start() }
        await room2.start()

        // Первое значимое событие — messagesRestored с «До обрыва»
        let restored = try await probe2.waitFor(timeout: .seconds(10)) {
            if case .messagesRestored = $0 { return true }; return false
        }
        guard case .messagesRestored(let messages, _) = restored else {
            Issue.record("Expected .messagesRestored as first significant event"); return
        }
        #expect(messages.contains { $0.text == "До обрыва" },
                "saved message must appear in messagesRestored")

        // Хост снова видит клиента
        _ = try await hostProbe.waitFor(timeout: .seconds(5)) {
            if case .participantsChanged(let ps) = $0 {
                return ps.contains { $0.id == clientIdentity.peerID }
            }
            return false
        }

        // В хранилище клиента ровно одна сессия с хостом (повторный вход — та же сессия)
        let sessions = try await storage.sessions(withPeer: hostIdentity.peerID)
        #expect(sessions.count == 1, "client must have exactly one session with host after rejoin")
    }
}

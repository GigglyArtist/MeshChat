// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

@Suite("RoomService", .serialized, .timeLimit(.minutes(1)))
struct RoomServiceTests {

    // MARK: - Вспомогательные методы

    private let peerID = UUID()

    func makeIdentity(nickname: String? = "Alice") -> FakeIdentityProvider {
        FakeIdentityProvider(nickname: nickname)
    }

    func makeService(
        identity: FakeIdentityProvider? = nil,
        storage: any StorageManaging = FailingStorage()
    ) -> (RoomService, FakeMeshNetworking) {
        let id = identity ?? makeIdentity()
        let network = FakeMeshNetworking()
        let secrets = RoomCredentialsFactory()
        let service = RoomService(identity: id, secrets: secrets, network: network, storage: storage)
        return (service, network)
    }

    // MARK: 1. createRoom → host room, has invite

    @Test("createRoom returns host room with invite set")
    func createRoomReturnsHostRoom() async throws {
        let (service, _) = makeService()
        let room = try await service.createRoom(password: "secret123")
        #expect(room.role == .host)
        #expect(room.invite != nil)
        #expect(room.localPeerID != UUID.init())   // non-nil UUID
    }

    // MARK: 2. createRoom: missing nickname → RoomError.nicknameMissing

    @Test("createRoom throws nicknameMissing when identity has no nickname")
    func createRoomNoNickname() async throws {
        let (service, _) = makeService(identity: makeIdentity(nickname: nil))
        do {
            _ = try await service.createRoom(password: "pass")
            Issue.record("Expected RoomError.nicknameMissing")
        } catch RoomError.nicknameMissing {
            // expected
        }
    }

    // MARK: 3. joinRoom → client room, invite is nil

    @Test("joinRoom returns client room with no invite")
    func joinRoomReturnsClientRoom() async throws {
        let (service, _) = makeService()
        let roomKey = Data(repeating: 0xAB, count: 32)
        let invite = RoomInvite(version: RoomInvite.currentVersion,
                                serviceName: UUID().uuidString,
                                roomKey: roomKey)
        let room = try await service.joinRoom(invite: invite)
        #expect(room.role == .client)
        #expect(room.invite == nil)
    }

    // MARK: 4. joinRoom: missing nickname → RoomError.nicknameMissing

    @Test("joinRoom throws nicknameMissing when identity has no nickname")
    func joinRoomNoNickname() async throws {
        let (service, _) = makeService(identity: makeIdentity(nickname: nil))
        let roomKey = Data(repeating: 0xAB, count: 32)
        let invite = RoomInvite(version: RoomInvite.currentVersion,
                                serviceName: UUID().uuidString,
                                roomKey: roomKey)
        do {
            _ = try await service.joinRoom(invite: invite)
            Issue.record("Expected RoomError.nicknameMissing")
        } catch RoomError.nicknameMissing {
            // expected
        }
    }

    // MARK: 5. createRoom: storage error is logged but room is still returned

    @Test("createRoom with failing storage still returns room (§11.1)")
    func createRoomStorageErrorNotFatal() async throws {
        let (service, _) = makeService(storage: FailingStorage())
        let room = try await service.createRoom(password: "anypassword")
        #expect(room.role == .host)
    }

    // MARK: 6. createRoom: FakeMeshNetworking records the created session

    @Test("createRoom creates exactly one host session via network")
    func createRoomCreatesHostSession() async throws {
        let (service, network) = makeService()
        _ = try await service.createRoom(password: "pass")
        #expect(network.hostSessions.count == 1)
        #expect(network.clientSessions.isEmpty)
    }

    // MARK: 7. joinRoom: FakeMeshNetworking records the created session

    @Test("joinRoom creates exactly one client session via network")
    func joinRoomCreatesClientSession() async throws {
        let (service, network) = makeService()
        let roomKey = Data(repeating: 0xAB, count: 32)
        let invite = RoomInvite(version: RoomInvite.currentVersion,
                                serviceName: UUID().uuidString,
                                roomKey: roomKey)
        _ = try await service.joinRoom(invite: invite)
        #expect(network.clientSessions.count == 1)
        #expect(network.hostSessions.isEmpty)
    }

    // MARK: 8. createRoom: session is created in storage

    @Test("createRoom saves session to storage with host role")
    func createRoomSavesSession() async throws {
        let controller = try PersistenceController(inMemory: true)
        let storage = CoreDataStorageManager(controller: controller)
        let (service, network) = makeService(storage: storage)

        _ = try await service.createRoom(password: "mypassword")

        let sessionID = network.hostSessions.first?.sessionID
        try #require(sessionID != nil)
        let info = try await storage.session(id: sessionID!)
        #expect(info?.role == .host)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import os

/// Фабрика активных комнат: создаёт хост-сессию или присоединяется к уже существующей (§11.2).
///
/// `nonisolated struct`; состояние — реестр текущей комнаты устройства (ADR-13).
/// Все копии структуры делят один реестр (ссылочный тип `ActiveRoomRegistry`).
/// Требования `RoomServicing` помечены `nonisolated`; вызов `@MainActor`-изолированных
/// фабрик сессий выполняется через `await MainActor.run { … }` (следствие ограничения
/// языка: синхронный `init` актора нельзя пометить `nonisolated`).
nonisolated struct RoomService: RoomServicing {

    private let identity: any IdentityProviding
    private let secrets: any RoomSecretProviding
    private let network: any MeshNetworking
    private let storage: any StorageManaging
    private let now: @Sendable () -> Date
    /// Реестр текущей комнаты устройства (ADR-13).
    private let registry: ActiveRoomRegistry

    private nonisolated static let logger = Logger(
        subsystem: "com.meshchat", category: "RoomService"
    )

    init(identity: any IdentityProviding,
         secrets: any RoomSecretProviding,
         network: any MeshNetworking,
         storage: any StorageManaging,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.identity = identity
        self.secrets = secrets
        self.network = network
        self.storage = storage
        self.now = now
        self.registry = ActiveRoomRegistry()
    }

    // MARK: - RoomServicing

    /// Перед созданием сессии покидает текущую комнату устройства, если она есть (ADR-13).
    nonisolated func createRoom(password: String) async throws -> any ActiveRoomHandling {
        guard let nickname = identity.nickname() else { throw RoomError.nicknameMissing }
        let peerID = try identity.permanentPeerID()
        let localIdentity = LocalIdentity(peerID: peerID, nickname: nickname)
        let secret = secrets.makeSecret(password: password)

        // Проверки завершены — покидаем текущую комнату перед созданием новой сессии (ADR-13).
        await registry.leaveCurrent()

        // MeshNetworking.makeHostSession and ActiveRoom.init are @MainActor-inferred.
        let (sessionID, room): (UUID, ActiveRoom) = await MainActor.run {
            let session = network.makeHostSession(identity: localIdentity, secret: secret)
            let sid = session.sessionID
            let room = ActiveRoom(session: session,
                                  storage: storage,
                                  localPeerID: peerID,
                                  invite: session.invite,
                                  sessionID: sid)
            return (sid, room)
        }

        // Storage error is logged but does not abort room creation (§11.1).
        do {
            try await storage.createSession(id: sessionID, role: .host, createdAt: now())
        } catch {
            Self.logger.error("createSession (host) failed: \(error, privacy: .public)")
        }

        await room.start()
        await registry.setCurrent(room)
        return room
    }

    /// Перед созданием сессии покидает текущую комнату устройства, если она есть (ADR-13).
    nonisolated func joinRoom(invite: RoomInvite) async throws -> any ActiveRoomHandling {
        guard let nickname = identity.nickname() else { throw RoomError.nicknameMissing }
        let peerID = try identity.permanentPeerID()
        let localIdentity = LocalIdentity(peerID: peerID, nickname: nickname)
        let secret = try secrets.secret(from: invite)

        // Проверки завершены — покидаем текущую комнату перед созданием новой сессии (ADR-13).
        await registry.leaveCurrent()

        // MeshNetworking.makeClientSession and ActiveRoom.init are @MainActor-inferred.
        let room: ActiveRoom = await MainActor.run {
            let session = network.makeClientSession(identity: localIdentity,
                                                    invite: invite,
                                                    secret: secret)
            return ActiveRoom(session: session,
                              storage: storage,
                              localPeerID: peerID,
                              invite: nil,
                              sessionID: nil)
        }

        await room.start()
        await registry.setCurrent(room)
        return room
    }
}

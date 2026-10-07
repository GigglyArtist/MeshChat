// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import os

/// Запущенная комната чата: читает события сетевой сессии, обновляет хранилище
/// и транслирует события слою Presentation (§11).
///
/// Цикл `readEvents` обрабатывает события из `session.events` строго последовательно,
/// ожидая каждую запись в хранилище. Это гарантирует: у клиента `createSession` всегда
/// завершается до `addParticipant` и `saveMessage` (§11.2).
actor ActiveRoom: ActiveRoomHandling {

    // MARK: - nonisolated let (ActiveRoomHandling)

    nonisolated let role: SessionRole
    nonisolated let localPeerID: UUID
    nonisolated let invite: RoomInvite?
    nonisolated let events: AsyncStream<RoomEvent>

    // MARK: - Actor-isolated state

    private let session: any ChatSessionManaging
    private let storage: any StorageManaging
    private let now: @Sendable () -> Date
    private var sessionID: UUID?
    private var participants: [UUID: PeerProfile] = [:]
    private var continuation: AsyncStream<RoomEvent>.Continuation?
    private var started = false

    private nonisolated static let logger = Logger(
        subsystem: "com.meshchat", category: "ActiveRoom"
    )

    // MARK: - Init

    /// - Parameters:
    ///   - sessionID: у хоста известен сразу; у клиента `nil` до события `established`.
    ///   - invite: QR-приглашение — только у хоста; у клиента `nil`.
    init(session: any ChatSessionManaging,
         storage: any StorageManaging,
         localPeerID: UUID,
         invite: RoomInvite?,
         sessionID: UUID?,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.storage = storage
        self.localPeerID = localPeerID
        self.invite = invite
        self.sessionID = sessionID
        self.role = session.role
        self.now = now
        var cont: AsyncStream<RoomEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // MARK: - Public actor API

    /// Запускает цикл событий и саму сессию. Идемпотентен.
    func start() async {
        guard !started else { return }
        started = true
        // session.start() runs the full session lifecycle loop; do not await it.
        Task { await session.start() }
        Task { [weak self] in await self?.readEvents() }
    }

    // MARK: - ActiveRoomHandling (nonisolated → actor hop)

    nonisolated func send(text: String) async throws {
        try await sendInternal(text: text)
    }

    nonisolated func leave() async {
        await leaveInternal()
    }

    nonisolated func appDidBecomeActive() async {
        await session.resumeAfterForeground()
    }

    // MARK: - Приватные методы

    private func sendInternal(text: String) async throws {
        let message = try await session.send(text: text)
        if let sid = sessionID {
            do {
                try await storage.saveMessage(message, inSession: sid)
            } catch {
                Self.logger.error("saveMessage (outgoing) failed: \(error, privacy: .public)")
            }
        }
        continuation?.yield(.messageAppended(message))
    }

    private func leaveInternal() async {
        await session.end()
    }

    private func readEvents() async {
        for await event in session.events {
            await handle(event)
        }
        continuation?.finish()
        continuation = nil
    }

    private func handle(_ event: SessionEvent) async {
        switch event {
        case .established(let sid):
            sessionID = sid
            do {
                try await storage.createSession(id: sid, role: .client, createdAt: now())
            } catch {
                Self.logger.error("createSession failed: \(error, privacy: .public)")
            }
            // Восстановить ранее сохранённые сообщения при повторном входе (ADR-12, §11.1).
            do {
                let messages = try await storage.messages(inSession: sid)
                if !messages.isEmpty {
                    let info = try? await storage.session(id: sid)
                    let knownPeers = info?.participants ?? []
                    continuation?.yield(.messagesRestored(messages, knownPeers: knownPeers))
                }
            } catch {
                Self.logger.error("messages restore failed: \(error, privacy: .public)")
            }

        case .participantJoined(let profile):
            participants[profile.id] = profile
            do {
                try await storage.upsertPeer(profile, seenAt: now())
                if let sid = sessionID {
                    try await storage.addParticipant(peerID: profile.id, toSession: sid)
                }
            } catch {
                Self.logger.error("storage join failed: \(error, privacy: .public)")
            }
            continuation?.yield(.participantsChanged(currentParticipants))
            continuation?.yield(.notice(.joined(nickname: profile.nickname)))

        case .participantLeft(let profile, let reason):
            participants.removeValue(forKey: profile.id)
            continuation?.yield(.participantsChanged(currentParticipants))
            continuation?.yield(.notice(.left(nickname: profile.nickname, reason: reason)))

        case .messageReceived(let message):
            if let sid = sessionID {
                do {
                    try await storage.saveMessage(message, inSession: sid)
                } catch {
                    Self.logger.error("saveMessage failed: \(error, privacy: .public)")
                }
            }
            continuation?.yield(.messageAppended(message))

        case .stateChanged(let state):
            if case .ended = state, let sid = sessionID {
                do {
                    try await storage.endSession(id: sid, endedAt: now())
                } catch {
                    Self.logger.error("endSession failed: \(error, privacy: .public)")
                }
            }
            continuation?.yield(.stateChanged(state))
        }
    }

    private var currentParticipants: [PeerProfile] {
        participants.values.sorted { $0.nickname < $1.nickname }
    }
}

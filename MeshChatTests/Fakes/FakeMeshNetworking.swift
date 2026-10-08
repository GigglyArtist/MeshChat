// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковая сетевая фабрика для тестов `RoomService`.
///
/// Каждый вызов `makeHostSession` / `makeClientSession` создаёт и регистрирует
/// `FakeChatSession`, которую тест может получить и управлять ею.
/// Все мутируемые поля защищены `NSLock` — отсюда `@unchecked Sendable`.
final class FakeMeshNetworking: MeshNetworking, @unchecked Sendable {

    private let lock = NSLock()
    private var _hostSessions: [FakeChatSession] = []
    private var _clientSessions: [FakeChatSession] = []

    /// Общий журнал вызовов для проверки порядка событий в тестах порядка (ADR-13).
    let callLog: RoomServiceCallLog

    init(callLog: RoomServiceCallLog = RoomServiceCallLog()) {
        self.callLog = callLog
    }

    /// Все хост-сессии, созданные через `makeHostSession`, в порядке создания.
    var hostSessions: [FakeChatSession] { lock.withLock { _hostSessions } }

    /// Все клиентские сессии, созданные через `makeClientSession`, в порядке создания.
    var clientSessions: [FakeChatSession] { lock.withLock { _clientSessions } }

    func makeHostSession(
        identity: LocalIdentity,
        secret: any RoomSecret
    ) -> any HostSessionManaging {
        callLog.append("makeHostSession")
        let session = FakeChatSession(role: .host, senderID: identity.peerID, callLog: callLog)
        lock.withLock { _hostSessions.append(session) }
        return session
    }

    func makeClientSession(
        identity: LocalIdentity,
        invite: RoomInvite,
        secret: any RoomSecret
    ) -> any ChatSessionManaging {
        callLog.append("makeClientSession")
        let session = FakeChatSession(role: .client, senderID: identity.peerID, callLog: callLog)
        lock.withLock { _clientSessions.append(session) }
        return session
    }
}

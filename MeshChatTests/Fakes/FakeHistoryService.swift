// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковая реализация `HistoryServicing` для тестов (§12.2).
///
/// `@unchecked Sendable`: состояние защищено `NSLock`; все публичные мутации
/// выполняются из `@MainActor`-тестов до вызова протокольных методов.
final class FakeHistoryService: HistoryServicing, @unchecked Sendable {

    private let lock = NSLock()

    // Настраиваемые ответы
    private var _peers: [PeerSummary]
    private var _sessions: [ChatSessionInfo]
    private var _transcript: SessionTranscript?
    private var _peersError: Error?
    private var _sessionsError: Error?
    private var _transcriptError: Error?
    private var _deleteError: Error?

    // Запись вызовов
    private var _deletedSessionIDs: [UUID] = []

    init(
        peers: [PeerSummary] = [],
        sessions: [ChatSessionInfo] = [],
        transcript: SessionTranscript? = nil,
        peersError: Error? = nil,
        transcriptError: Error? = nil
    ) {
        _peers = peers
        _sessions = sessions
        _transcript = transcript
        _peersError = peersError
        _transcriptError = transcriptError
    }

    // MARK: Публичный API для тестов

    var peers: [PeerSummary] {
        get { lock.withLock { _peers } }
        set { lock.withLock { _peers = newValue } }
    }

    var sessions: [ChatSessionInfo] {
        get { lock.withLock { _sessions } }
        set { lock.withLock { _sessions = newValue } }
    }

    var deleteError: Error? {
        get { lock.withLock { _deleteError } }
        set { lock.withLock { _deleteError = newValue } }
    }

    var deletedSessionIDs: [UUID] { lock.withLock { _deletedSessionIDs } }

    // MARK: HistoryServicing

    nonisolated func peerSummaries() async throws -> [PeerSummary] {
        try lock.withLock {
            if let e = _peersError { throw e }
            return _peers
        }
    }

    nonisolated func sessions(withPeer peerID: UUID) async throws -> [ChatSessionInfo] {
        try lock.withLock {
            if let e = _sessionsError { throw e }
            return _sessions
        }
    }

    nonisolated func transcript(sessionID: UUID) async throws -> SessionTranscript {
        try lock.withLock {
            if let e = _transcriptError { throw e }
            guard let t = _transcript else { throw StorageError.sessionNotFound(sessionID) }
            return t
        }
    }

    nonisolated func deleteSession(id: UUID) async throws {
        try lock.withLock {
            if let e = _deleteError { throw e }
            _deletedSessionIDs.append(id)
        }
    }
}

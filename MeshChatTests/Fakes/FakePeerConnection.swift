// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
@testable import MeshChat

/// Фейковое соединение для юнит-тестов сессий (§7.8).
///
/// Все мутируемые поля защищены `NSLock` — отсюда `@unchecked Sendable`.
final class FakePeerConnection: PeerConnection, @unchecked Sendable {

    nonisolated let connectionID: UUID
    nonisolated let events: AsyncStream<ConnectionEvent>

    private let lock = NSLock()
    private var _sentPackets: [Packet] = []
    private var continuation: AsyncStream<ConnectionEvent>.Continuation?
    // weak reference предотвращает retain-цикл между парой
    private weak var _peer: FakePeerConnection?
    private let startReady: Bool
    /// Обрыв провода (§9.6): `true` — пакеты не доставляются, состояние остаётся `.ready`.
    private var _severed: Bool = false

    /// Все пакеты, отправленные через `send(_:)`.
    nonisolated var sentPackets: [Packet] { lock.withLock { _sentPackets } }

    // MARK: - Фабрика пар

    /// Создаёт два связанных конца: `send` на одном → `.packet` на другом.
    ///
    /// - Parameter startReady: если `true`, `start()` немедленно эмитит `.state(.ready)`.
    static func makePair(startReady: Bool = true) -> (FakePeerConnection, FakePeerConnection) {
        let a = FakePeerConnection(startReady: startReady)
        let b = FakePeerConnection(startReady: startReady)
        a.lock.withLock { a._peer = b }
        b.lock.withLock { b._peer = a }
        return (a, b)
    }

    private init(startReady: Bool) {
        self.connectionID = UUID()
        self.startReady = startReady
        var cont: AsyncStream<ConnectionEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    // MARK: - PeerConnection

    nonisolated func start() {
        if startReady { emit(.state(.ready)) }
    }

    nonisolated func send(_ packet: Packet) async throws {
        let deliver: Bool = lock.withLock {
            _sentPackets.append(packet)
            return !_severed
        }
        if deliver { peer?.emit(.packet(packet)) }
    }

    nonisolated func cancel() {
        emit(.state(.cancelled))
        closeStream()
        let p = peer
        p?.emit(.state(.cancelled))
        p?.closeStream()
    }

    // MARK: - Вспомогательные методы для тестов

    /// «Обрыв провода»: оба конца остаются в `.ready`, `send` успешно записывает пакет,
    /// но доставки на другой конец не происходит — так моделируется тишина (§9.6).
    nonisolated func sever() {
        markSevered()
        peer?.markSevered()
    }

    /// Отправляет произвольное событие в поток этого конца.
    nonisolated func emit(_ event: ConnectionEvent) {
        lock.withLock { _ = continuation?.yield(event) }
    }

    /// Имитирует переход в `.ready` (используется при `startReady: false`).
    nonisolated func emitReady() { emit(.state(.ready)) }

    /// Имитирует разрыв: `.failed` + завершение обоих потоков.
    nonisolated func emitFailure(_ issue: NetworkIssue = .other("fake failure")) {
        emit(.state(.failed(issue)))
        closeStream()
        let p = peer
        p?.emit(.state(.cancelled))
        p?.closeStream()
    }

    // MARK: - Приватные хелперы

    nonisolated private func markSevered() {
        lock.withLock { _severed = true }
    }

    nonisolated private func closeStream() {
        lock.withLock { continuation?.finish(); continuation = nil }
    }

    nonisolated private var peer: FakePeerConnection? { lock.withLock { _peer } }
}

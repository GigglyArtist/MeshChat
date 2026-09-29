// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing

/// Собирает события из `AsyncStream` и позволяет ждать конкретного события.
///
/// Все мутируемые поля защищены `NSLock` — отсюда `@unchecked Sendable`.
final class EventProbe<Element: Sendable>: @unchecked Sendable {

    private let lock = NSLock()
    private var _events: [Element] = []
    private var _finished = false
    // var? с дефолтом nil → Phase 1 завершается без захвата self; Task создаётся в Phase 2.
    private var task: Task<Void, Never>? = nil

    var events: [Element] { lock.withLock { _events } }
    var isFinished: Bool { lock.withLock { _finished } }

    init(stream: AsyncStream<Element>) {
        // Phase 1 завершена (все свойства имеют значения); self доступен для слабого захвата.
        task = Task { [weak self, stream] in
            for await event in stream {
                self?.append(event)
            }
            self?.markFinished()
        }
    }

    deinit { task?.cancel() }

    private func append(_ event: Element) {
        lock.withLock { _events.append(event) }
    }

    private func markFinished() {
        lock.withLock { _finished = true }
    }

    // MARK: - Ожидание

    /// Ожидает первое событие, удовлетворяющее предикату.
    ///
    /// - Parameters:
    ///   - timeout: максимальное время ожидания
    ///   - predicate: условие отбора
    /// - Returns: первое подходящее событие
    /// - Throws: `EventProbeError` при таймауте
    func waitFor(timeout: Duration = .seconds(5), _ predicate: (Element) -> Bool) async throws -> Element {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let found = lock.withLock({ _events.first(where: predicate) }) { return found }
            if isFinished { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        if let found = lock.withLock({ _events.first(where: predicate) }) { return found }
        throw EventProbeError.timeout(received: events.map { "\($0)" })
    }

    /// Ожидает не менее `count` событий, удовлетворяющих предикату.
    func waitFor(count: Int, timeout: Duration = .seconds(5), _ predicate: (Element) -> Bool) async throws -> [Element] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let matching = lock.withLock { _events.filter(predicate) }
            if matching.count >= count { return matching }
            if isFinished { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let matching = lock.withLock { _events.filter(predicate) }
        if matching.count >= count { return matching }
        throw EventProbeError.timeout(received: events.map { "\($0)" })
    }

    /// Ожидает завершения потока событий.
    func waitForFinish(timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if isFinished { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        if isFinished { return }
        throw EventProbeError.timeout(received: events.map { "\($0)" })
    }
}

/// Ошибки `EventProbe`.
nonisolated enum EventProbeError: Error {
    case timeout(received: [String])
}

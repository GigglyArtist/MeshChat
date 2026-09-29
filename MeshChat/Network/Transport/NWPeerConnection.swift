// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Network
import os

/// Обёртка над `NWConnection` с API на `AsyncStream` (§7.4).
///
/// Все колбэки `NWConnection` выполняются на одной приватной последовательной очереди.
/// Изменяемые поля (`assembler`, `isStarted`, `isFinished`) трогаются только на ней.
/// Поэтому класс помечен `@unchecked Sendable` — реальная потокобезопасность обеспечена очередью.
nonisolated final class NWPeerConnection: PeerConnection, @unchecked Sendable {

    // Logger — Sendable struct; nonisolated static let безопасен без nonisolated(unsafe).
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "meshchat",
        category: "network"
    )

    let connectionID = UUID()

    private let connection: NWConnection
    // Приватная последовательная очередь — все колбэки NWConnection выполняются на ней.
    private let queue: DispatchQueue

    private var assembler = FrameAssembler()
    private let codec = PacketCodec()

    private var isStarted = false
    private var isFinished = false

    let events: AsyncStream<ConnectionEvent>
    private let continuation: AsyncStream<ConnectionEvent>.Continuation

    // MARK: - Инициализаторы

    /// Инициализатор для **входящих** соединений от `NWListener`.
    init(connection: NWConnection) {
        self.connection = connection
        self.queue = DispatchQueue(label: "meshchat.connection.\(UUID().uuidString)", qos: .utility)
        (events, continuation) = AsyncStream.makeStream(of: ConnectionEvent.self)
        setupHandlers()
    }

    /// Инициализатор для **исходящих** соединений (коннектор, тест через 127.0.0.1).
    convenience init(endpoint: NWEndpoint, parameters: NWParameters) {
        self.init(connection: NWConnection(to: endpoint, using: parameters))
    }

    // MARK: - PeerConnection

    nonisolated func start() {
        queue.async { [self] in
            guard !isStarted else { return }
            isStarted = true
            connection.start(queue: queue)
        }
    }

    nonisolated func send(_ packet: Packet) async throws {
        let frame: Data
        do { frame = try codec.encodeFrame(packet) }
        catch { throw NetworkError.sendFailed(error.localizedDescription) }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: NetworkError.sendFailed(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    nonisolated func cancel() {
        queue.async { [self] in
            connection.cancel()
        }
    }

    // MARK: - Настройка колбэков

    private func setupHandlers() {
        // Когда потребитель перестаёт читать события — закрываем соединение.
        continuation.onTermination = { [weak self] _ in
            self?.connection.cancel()
        }

        connection.stateUpdateHandler = { [weak self] state in
            self?.handleState(state)
        }

        connection.viabilityUpdateHandler = { [weak self] isViable in
            self?.continuation.yield(.viability(isViable))
        }
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .setup, .preparing:
            continuation.yield(.state(.preparing))

        case .ready:
            continuation.yield(.state(.ready))
            startReceiving()

        case .waiting(let error):
            continuation.yield(.state(.waiting(error.issue)))

        case .failed(let error):
            let issue = error.issue
            NWPeerConnection.logger.info("[\(self.connectionID)] failed: \(issue, privacy: .public)")
            yieldFinal(.state(.failed(issue)))

        case .cancelled:
            NWPeerConnection.logger.info("[\(self.connectionID)] cancelled")
            yieldFinal(.state(.cancelled))

        @unknown default:
            NWPeerConnection.logger.warning("[\(self.connectionID)] unknown NWConnection state — ignoring")
        }
    }

    // MARK: - Чтение кадров

    private func startReceiving() {
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                do {
                    let frames = try assembler.append(data)
                    for frame in frames {
                        processFrame(frame)
                    }
                } catch let codecError as PacketCodecError {
                    // Битый заголовок — нарушение протокола, соединение закрывается.
                    continuation.yield(.protocolViolation(codecError))
                    connection.cancel()
                    return
                } catch {
                    continuation.yield(.protocolViolation(.malformedJSON))
                    connection.cancel()
                    return
                }
            }

            if isComplete {
                // Собеседник закрыл поток — закрываем своё соединение.
                connection.cancel()
                return
            }

            if error != nil {
                // Ошибка получения — stateUpdateHandler уже зарегистрирует переход в .failed.
                return
            }

            // Читаем следующий кусок.
            receive()
        }
    }

    private func processFrame(_ json: Data) {
        do {
            let packet = try codec.decodePayload(json)
            continuation.yield(.packet(packet))
        } catch PacketCodecError.unknownType(let t) {
            // Неизвестный тип — соединение продолжает работать (§8.4).
            NWPeerConnection.logger.info("[\(self.connectionID)] unknown packet type '\(t, privacy: .public)' — continuing")
            continuation.yield(.protocolViolation(.unknownType(t)))
        } catch let codecError as PacketCodecError {
            // Любая другая ошибка декодирования — нарушение протокола, закрыть.
            continuation.yield(.protocolViolation(codecError))
            connection.cancel()
        } catch {
            continuation.yield(.protocolViolation(.malformedJSON))
            connection.cancel()
        }
    }

    // MARK: - Завершение потока событий

    private func yieldFinal(_ event: ConnectionEvent) {
        guard !isFinished else { return }
        isFinished = true
        continuation.yield(event)
        continuation.finish()
    }
}

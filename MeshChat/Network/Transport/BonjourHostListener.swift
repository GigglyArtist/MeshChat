// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Network
import os

/// Bonjour-listener: публикует TCP-сервис и отдаёт поток входящих соединений (§7.1, §7.4).
///
/// Изменяемые поля (`listener`, `continuation`, `isRunning`) защищены `NSLock`.
/// Поэтому класс помечен `@unchecked Sendable` — реальная потокобезопасность обеспечена замком.
nonisolated final class BonjourHostListener: HostListening, @unchecked Sendable {

    // Logger — Sendable struct; nonisolated static let безопасен без nonisolated(unsafe).
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "meshchat",
        category: "network"
    )

    private let configuration: NetworkConfiguration
    private let lock = NSLock()
    private var nwListener: NWListener?
    private var continuation: AsyncStream<ListenerEvent>.Continuation?
    private var isRunning = false

    nonisolated init(configuration: NetworkConfiguration) {
        self.configuration = configuration
    }

    // MARK: - HostListening

    nonisolated func start(serviceName: String, security: ChannelSecurity) throws -> AsyncStream<ListenerEvent> {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else {
            throw NetworkError.listenerFailed("Listener is already running")
        }
        isRunning = true

        let (stream, cont) = AsyncStream.makeStream(of: ListenerEvent.self)
        continuation = cont

        let listener: NWListener
        do {
            listener = try NWListener(using: .meshChat(security: security))
        } catch {
            isRunning = false
            continuation = nil
            throw NetworkError.listenerFailed(error.localizedDescription)
        }
        listener.service = NWListener.Service(name: serviceName, type: configuration.serviceType)
        nwListener = listener

        let queue = DispatchQueue(label: "meshchat.listener.\(serviceName)", qos: .utility)
        setupHandlers(for: listener)
        listener.start(queue: queue)

        return stream
    }

    nonisolated func stop() {
        lock.lock()
        let listener = nwListener
        let cont = continuation
        nwListener = nil
        continuation = nil
        isRunning = false
        lock.unlock()

        listener?.cancel()
        cont?.finish()
    }

    // MARK: - Настройка колбэков listener'а

    private func setupHandlers(for listener: NWListener) {
        listener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let peerConn = NWPeerConnection(connection: connection)
            lock.lock()
            let cont = continuation
            lock.unlock()
            cont?.yield(.incoming(peerConn))
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        lock.lock()
        let cont = continuation
        lock.unlock()

        switch state {
        case .ready:
            let port = nwListener?.port?.rawValue ?? 0
            BonjourHostListener.logger.info("Listener ready on port \(port, privacy: .public)")
            cont?.yield(.ready(port: port))

        case .failed(let error):
            let issue = error.issue
            BonjourHostListener.logger.error("Listener failed: \(issue, privacy: .public)")
            finishWithIssue(issue, cont: cont)

        case .waiting(let error):
            let issue = error.issue
            if case .localNetworkDenied = issue {
                BonjourHostListener.logger.error("Listener denied local network access")
                // Нет разрешения «Локальная сеть» — терминальная ошибка.
                nwListener?.cancel()
                finishWithIssue(.localNetworkDenied, cont: cont)
            } else {
                BonjourHostListener.logger.warning("Listener waiting: \(issue, privacy: .public)")
                // Прочее ожидание — не завершаем, только логируем.
            }

        case .cancelled:
            BonjourHostListener.logger.info("Listener cancelled")
            lock.lock()
            continuation = nil
            lock.unlock()
            cont?.finish()

        case .setup:
            break

        @unknown default:
            BonjourHostListener.logger.warning("Listener unknown state — ignoring")
        }
    }

    private func finishWithIssue(_ issue: NetworkIssue, cont: AsyncStream<ListenerEvent>.Continuation?) {
        lock.lock()
        nwListener = nil
        continuation = nil
        isRunning = false
        lock.unlock()

        cont?.yield(.failed(issue))
        cont?.finish()
    }
}

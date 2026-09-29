// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Network
import Testing
@testable import MeshChat

/// Пара установленных соединений клиент–сервер для транспортных тестов.
struct ConnectedPair {
    let client: any PeerConnection
    let clientProbe: EventProbe<ConnectionEvent>
    let server: any PeerConnection
    let serverProbe: EventProbe<ConnectionEvent>
}

/// Поднимает `BonjourHostListener` на случайном порту и предоставляет вспомогательные
/// методы для соединения через `127.0.0.1` в тестах (§7.1, §7.4).
///
/// Мутируемые поля отсутствуют после `init` — класс Sendable без проблем.
final class LoopbackHarness: @unchecked Sendable {

    let listener: BonjourHostListener
    let listenerProbe: EventProbe<ListenerEvent>
    let port: UInt16

    private init(listener: BonjourHostListener,
                 listenerProbe: EventProbe<ListenerEvent>,
                 port: UInt16) {
        self.listener = listener
        self.listenerProbe = listenerProbe
        self.port = port
    }

    // MARK: - Запуск

    /// Поднимает listener и ждёт события `.ready(port:)`.
    static func start(serviceName: String? = nil) async throws -> LoopbackHarness {
        let name = serviceName ?? "LoopbackTest-\(UUID().uuidString.prefix(8))"
        let config = NetworkConfiguration.standard
        let listener = BonjourHostListener(configuration: config)
        let stream = try listener.start(serviceName: name, security: .plaintext)
        let probe = EventProbe<ListenerEvent>(stream: stream)

        let readyEvent = try await probe.waitFor(timeout: .seconds(5)) { event in
            if case .ready = event { return true }
            return false
        }
        guard case .ready(let port) = readyEvent else {
            throw NSError(domain: "LoopbackHarness", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Expected .ready event"])
        }
        return LoopbackHarness(listener: listener, listenerProbe: probe, port: port)
    }

    // MARK: - Соединение

    /// Устанавливает пару соединений через `127.0.0.1` и ждёт `.state(.ready)` на обоих концах.
    func connect(security: ChannelSecurity = .plaintext) async throws -> ConnectedPair {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "LoopbackHarness", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }
        // Создаём клиента до start(), чтобы EventProbe не пропустил события.
        let client = NWPeerConnection(
            endpoint: .hostPort(host: "127.0.0.1", port: nwPort),
            parameters: .meshChat(security: security)
        )
        let clientProbe = EventProbe<ConnectionEvent>(stream: client.events)
        client.start()

        // Ждём входящее соединение на стороне listener'а.
        let incomingEvent = try await listenerProbe.waitFor(timeout: .seconds(5)) { event in
            if case .incoming = event { return true }
            return false
        }
        guard case .incoming(let serverConn) = incomingEvent else {
            throw NSError(domain: "LoopbackHarness", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Expected .incoming event"])
        }
        // Создаём probe до start(), чтобы не пропустить события.
        let serverProbe = EventProbe<ConnectionEvent>(stream: serverConn.events)
        serverConn.start()

        // Ждём .state(.ready) на обоих концах.
        _ = try await clientProbe.waitFor(timeout: .seconds(5)) { event in
            if case .state(.ready) = event { return true }
            return false
        }
        _ = try await serverProbe.waitFor(timeout: .seconds(5)) { event in
            if case .state(.ready) = event { return true }
            return false
        }
        return ConnectedPair(client: client, clientProbe: clientProbe,
                             server: serverConn, serverProbe: serverProbe)
    }

    // MARK: - Сырое TCP-соединение

    /// Создаёт незапущенное `NWConnection` с чистым TCP (без codec) к порту listener'а.
    func makeRawConnection() -> NWConnection {
        let nwPort = NWEndpoint.Port(rawValue: port)!
        return NWConnection(
            to: .hostPort(host: "127.0.0.1", port: nwPort),
            using: NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        )
    }

    // MARK: - Остановка

    func stop() { listener.stop() }
}

// MARK: - Вспомогательные функции для сырых соединений

/// Запускает `NWConnection` и ждёт перехода в `.ready`.
func startRaw(_ conn: NWConnection) async throws {
    // OnceResumer позволяет безопасно вызывать resume только один раз из DispatchQueue колбэка.
    final class OnceResumer: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<Void, Error>?
        init(_ cont: CheckedContinuation<Void, Error>) { self.cont = cont }
        func resolve(_ result: Result<Void, Error>) {
            lock.lock()
            let c = cont; cont = nil
            lock.unlock()
            c?.resume(with: result)
        }
    }
    let queue = DispatchQueue(label: "meshchat.test.raw.\(UUID().uuidString)")
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        let resumer = OnceResumer(cont)
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:   resumer.resolve(.success(()))
            case .failed(let e): resumer.resolve(.failure(e))
            case .cancelled:     resumer.resolve(.failure(CancellationError()))
            default: break
            }
        }
        conn.start(queue: queue)
    }
}

/// Отправляет `data` через `NWConnection` и ждёт `contentProcessed`.
func sendRaw(_ conn: NWConnection, data: Data) async {
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        conn.send(content: data, completion: .contentProcessed { _ in
            cont.resume()
        })
    }
}

/// Строит кадр с 4-байтовым big-endian заголовком длины + тело `json`.
func makeRawFrame(_ json: String) -> Data {
    let body = Data(json.utf8)
    let length = UInt32(body.count)
    var frame = Data(capacity: 4 + body.count)
    frame.append(UInt8(length >> 24))
    frame.append(UInt8((length >> 16) & 0xFF))
    frame.append(UInt8((length >> 8) & 0xFF))
    frame.append(UInt8(length & 0xFF))
    frame.append(contentsOf: body)
    return frame
}

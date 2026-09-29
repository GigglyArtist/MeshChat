// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Network
import Testing
@testable import MeshChat

// MARK: - Производные PSK из §6.3 golden values

private let goldenSalt = Data(0x00...0x1f)

/// `"correct horse"` → tlsPreSharedKey (§6.3).
private let psk1: Data = {
    let roomKey = RoomCredentialsFactory.deriveRoomKey(password: "correct horse", salt: goldenSalt)
    // try! допустим в тестах; приложение-то никогда это не вызовет.
    return (try! RoomCredentials(roomKeyData: roomKey)).tlsPreSharedKey
}()

/// `"пароль1234"` → tlsPreSharedKey (§6.3).
private let psk2: Data = {
    let roomKey = RoomCredentialsFactory.deriveRoomKey(password: "пароль1234", salt: goldenSalt)
    return (try! RoomCredentials(roomKeyData: roomKey)).tlsPreSharedKey
}()

@Suite("TLS-PSK transport", .serialized, .timeLimit(.minutes(1)))
struct TLSTransportTests {

    // MARK: - Тест 1: одинаковый PSK → оба .ready, обмен пакетом

    @Test("same PSK: both reach .ready and exchange a packet")
    func samePSKConnects() async throws {
        let harness = try await LoopbackHarness.start(security: .tlsPSK(psk1))
        defer { harness.stop() }

        let pair: ConnectedPair
        do {
            pair = try await harness.connect(security: .tlsPSK(psk1))
        } catch {
            // Если оба конца не добрались до .ready — выводим все события для диагностики.
            let listenerEvents = harness.listenerProbe.events.map { "\($0)" }
            Issue.record("samePSKConnects failed: \(error); listenerEvents: \(listenerEvents)")
            throw error
        }
        defer { pair.client.cancel(); pair.server.cancel() }

        let msg = MessagePayload(messageID: UUID(), senderID: UUID(),
                                 text: "tls-hello", timestamp: Date())
        try await pair.client.send(.chatMessage(msg))

        _ = try await pair.serverProbe.waitFor(timeout: .seconds(5)) {
            if case .packet(.chatMessage(let m)) = $0 { return m.messageID == msg.messageID }
            return false
        }
    }

    // MARK: - Тест 2: разные PSK → нет .ready и .packet за 3 с

    @Test("different PSK: no .ready, no .packet within 3s")
    func differentPSKBlocked() async throws {
        let harness = try await LoopbackHarness.start(security: .tlsPSK(psk1))
        defer { harness.stop() }

        guard let nwPort = NWEndpoint.Port(rawValue: harness.port) else {
            Issue.record("Invalid port"); return
        }
        // Клиент с другим PSK подключается по 127.0.0.1 (Bonjour-сервис может зависнуть при mismatch).
        let client = NWPeerConnection(
            endpoint: .hostPort(host: "127.0.0.1", port: nwPort),
            parameters: .meshChat(security: .tlsPSK(psk2))
        )
        let clientProbe = EventProbe<ConnectionEvent>(stream: client.events)
        client.start()
        defer { client.cancel() }

        // Ждём входящее соединение — listener его принимает, но TLS не договаривается.
        let incomingEvent = try await harness.listenerProbe.waitFor(timeout: .seconds(5)) {
            if case .incoming = $0 { return true }; return false
        }
        guard case .incoming(let serverConn) = incomingEvent else {
            Issue.record("Expected .incoming"); return
        }
        let serverProbe = EventProbe<ConnectionEvent>(stream: serverConn.events)
        serverConn.start()
        defer { serverConn.cancel() }

        // Выдерживаем 3 секунды и убеждаемся, что .ready и .packet не появились.
        try await Task.sleep(for: .seconds(3))

        let serverEvents = serverProbe.events
        let clientEvents = clientProbe.events

        let serverReady = serverEvents.contains { if case .state(.ready) = $0 { return true }; return false }
        let serverPacket = serverEvents.contains { if case .packet = $0 { return true }; return false }
        let clientReady = clientEvents.contains { if case .state(.ready) = $0 { return true }; return false }
        let clientPacket = clientEvents.contains { if case .packet = $0 { return true }; return false }

        #expect(!serverReady, "server should not reach .ready with wrong PSK")
        #expect(!serverPacket, "server should not receive any packet with wrong PSK")
        #expect(!clientReady, "client should not reach .ready with wrong PSK")
        #expect(!clientPacket, "client should not receive any packet with wrong PSK")

        // Диагностическое примечание: был ли .waiting(.tlsFailure)?
        let tlsWaiting = clientEvents.contains {
            if case .state(.waiting(.tlsFailure)) = $0 { return true }; return false
        }
        if tlsWaiting {
            // Ожидаемое поведение на 127.0.0.1: клиент уходит в .waiting(.tlsFailure(_)).
        }
    }

    // MARK: - Тест 3: plaintext-клиент → TLS-listener нет .ready и .packet за 3 с

    /// Plaintext-клиент может установить TCP-соединение (и увидит .ready), но TLS-сервер
    /// не завершит TLS-рукопожатие: сервер не достигнет .ready и не получит пакетов.
    @Test("plaintext client to TLS listener: server never .ready, no packets exchanged within 3s")
    func plaintextClientToTLSListener() async throws {
        let harness = try await LoopbackHarness.start(security: .tlsPSK(psk1))
        defer { harness.stop() }

        guard let nwPort = NWEndpoint.Port(rawValue: harness.port) else {
            Issue.record("Invalid port"); return
        }
        let client = NWPeerConnection(
            endpoint: .hostPort(host: "127.0.0.1", port: nwPort),
            parameters: .meshChat(security: .plaintext)
        )
        let clientProbe = EventProbe<ConnectionEvent>(stream: client.events)
        client.start()
        defer { client.cancel() }

        let incomingEvent = try await harness.listenerProbe.waitFor(timeout: .seconds(5)) {
            if case .incoming = $0 { return true }; return false
        }
        guard case .incoming(let serverConn) = incomingEvent else {
            Issue.record("Expected .incoming"); return
        }
        let serverProbe = EventProbe<ConnectionEvent>(stream: serverConn.events)
        serverConn.start()
        defer { serverConn.cancel() }

        try await Task.sleep(for: .seconds(3))

        let serverEvents = serverProbe.events
        let clientEvents = clientProbe.events

        // Сервер (TLS) не может завершить рукопожатие с plaintext-клиентом.
        let serverReady  = serverEvents.contains { if case .state(.ready) = $0 { return true }; return false }
        let serverPacket = serverEvents.contains { if case .packet = $0 { return true }; return false }
        // Клиент — plaintext, TCP доходит до .ready, но пакетов с сервера не получает.
        let clientPacket = clientEvents.contains { if case .packet = $0 { return true }; return false }

        #expect(!serverReady,  "TLS server should not reach .ready with plaintext client")
        #expect(!serverPacket, "TLS server should not receive any packet from plaintext client")
        #expect(!clientPacket, "plaintext client should not receive any app packet from TLS server")
    }
}

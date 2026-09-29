// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Network
import Testing
@testable import MeshChat

@Suite("Bonjour transport end-to-end")
struct BonjourTransportTests {

    /// Конец-в-конец: `BonjourClientConnector` находит хост через mDNS и обменивается пакетом.
    ///
    /// Timeout ожиданий — 10 с, так как mDNS-разрешение медленнее прямого подключения по IP.
    @Test("BonjourClientConnector plaintext one-packet exchange", .timeLimit(.minutes(1)))
    func bonjourPlaintextExchange() async throws {
        let serviceName = "BonjourTest-\(UUID().uuidString.prefix(8))"
        let config = NetworkConfiguration.standard

        // Поднимаем listener.
        let listener = BonjourHostListener(configuration: config)
        let listenerStream = try listener.start(serviceName: serviceName, security: .plaintext)
        let listenerProbe = EventProbe<ListenerEvent>(stream: listenerStream)
        defer { listener.stop() }

        _ = try await listenerProbe.waitFor(timeout: .seconds(10)) {
            if case .ready = $0 { return true }; return false
        }

        // Создаём клиента через BonjourClientConnector (Bonjour-эндпоинт, mDNS).
        let connector = BonjourClientConnector(configuration: config)
        let client = connector.makeConnection(serviceName: serviceName, security: .plaintext)
        let clientProbe = EventProbe<ConnectionEvent>(stream: client.events)
        client.start()

        // Ждём входящее соединение.
        let incomingEvent = try await listenerProbe.waitFor(timeout: .seconds(10)) {
            if case .incoming = $0 { return true }; return false
        }
        guard case .incoming(let serverConn) = incomingEvent else {
            Issue.record("Expected .incoming event from Bonjour listener"); return
        }
        let serverProbe = EventProbe<ConnectionEvent>(stream: serverConn.events)
        serverConn.start()
        defer { serverConn.cancel() }
        defer { client.cancel() }

        // Ждём .state(.ready) с обеих сторон.
        _ = try await clientProbe.waitFor(timeout: .seconds(10)) {
            if case .state(.ready) = $0 { return true }; return false
        }
        _ = try await serverProbe.waitFor(timeout: .seconds(10)) {
            if case .state(.ready) = $0 { return true }; return false
        }

        // Отправляем один пакет и убеждаемся, что сервер его получил.
        let msg = MessagePayload(messageID: UUID(), senderID: UUID(),
                                 text: "bonjour-test", timestamp: Date())
        try await client.send(.chatMessage(msg))

        _ = try await serverProbe.waitFor(timeout: .seconds(10)) {
            if case .packet(.chatMessage(let m)) = $0 { return m.messageID == msg.messageID }
            return false
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Network
import Testing
@testable import MeshChat

@Suite("Plaintext transport", .serialized, .timeLimit(.minutes(1)))
struct PlaintextTransportTests {

    // MARK: - Тест 1: listener готов

    @Test("listener emits ready(port:) with port > 0")
    func listenerReady() async throws {
        let harness = try await LoopbackHarness.start()
        defer { harness.stop() }
        #expect(harness.port > 0)
    }

    // MARK: - Тест 2: roundtrip chatMessage

    @Test("chatMessage roundtrip client→server and server→client")
    func chatMessageRoundtrip() async throws {
        let harness = try await LoopbackHarness.start()
        defer { harness.stop() }
        let pair = try await harness.connect()
        defer { pair.client.cancel(); pair.server.cancel() }

        let sent = makeTestMsg(text: "hello")
        try await pair.client.send(.chatMessage(sent))
        _ = try await pair.serverProbe.waitFor {
            if case .packet(.chatMessage(let m)) = $0 { return m.messageID == sent.messageID }
            return false
        }

        let reply = makeTestMsg(text: "world")
        try await pair.server.send(.chatMessage(reply))
        _ = try await pair.clientProbe.waitFor {
            if case .packet(.chatMessage(let m)) = $0 { return m.messageID == reply.messageID }
            return false
        }
    }

    // MARK: - Тест 3: 200 пакетов в каждую сторону, порядок сохранён

    @Test("200 packets each direction, order preserved")
    func bulkPacketsOrdered() async throws {
        let harness = try await LoopbackHarness.start()
        defer { harness.stop() }
        let pair = try await harness.connect()
        defer { pair.client.cancel(); pair.server.cancel() }

        // Отправляем по 200 пакетов одновременно в обе стороны.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<200 {
                    try await pair.client.send(.chatMessage(makeTestMsg(text: "c2s-\(i)")))
                }
            }
            group.addTask {
                for i in 0..<200 {
                    try await pair.server.send(.chatMessage(makeTestMsg(text: "s2c-\(i)")))
                }
            }
            try await group.waitForAll()
        }

        let serverReceived = try await pair.serverProbe.waitFor(count: 200, timeout: .seconds(10)) {
            if case .packet = $0 { return true }; return false
        }
        let clientReceived = try await pair.clientProbe.waitFor(count: 200, timeout: .seconds(10)) {
            if case .packet = $0 { return true }; return false
        }

        // Порядок пакетов определяется TCP — проверяем последовательность.
        for (i, event) in serverReceived.enumerated() {
            guard case .packet(.chatMessage(let m)) = event else { continue }
            #expect(m.text == "c2s-\(i)")
        }
        for (i, event) in clientReceived.enumerated() {
            guard case .packet(.chatMessage(let m)) = event else { continue }
            #expect(m.text == "s2c-\(i)")
        }
    }

    // MARK: - Тест 4: большое сообщение (30 000 кириллических символов ≈ 60 КБ < 64 КиБ)

    @Test("large message with 30 000 Cyrillic chars transfers correctly")
    func largeCyrillicMessage() async throws {
        let harness = try await LoopbackHarness.start()
        defer { harness.stop() }
        let pair = try await harness.connect()
        defer { pair.client.cancel(); pair.server.cancel() }

        // Символ 'А' (U+0410) занимает 2 байта в UTF-8 → 30 000 × 2 = 60 000 байт < 65 536.
        let longText = String(repeating: "А", count: 30_000)
        let msg = makeTestMsg(text: longText)
        try await pair.client.send(.chatMessage(msg))

        _ = try await pair.serverProbe.waitFor(timeout: .seconds(5)) {
            if case .packet(.chatMessage(let m)) = $0 { return m.messageID == msg.messageID }
            return false
        }
    }

    // MARK: - Тест 5: server.cancel() закрывает клиента

    @Test("server cancel propagates to client within 5s")
    func serverCancelPropagates() async throws {
        let harness = try await LoopbackHarness.start()
        defer { harness.stop() }
        let pair = try await harness.connect()

        pair.server.cancel()

        _ = try await pair.clientProbe.waitFor(timeout: .seconds(5)) { event in
            switch event {
            case .state(.cancelled), .state(.failed(_)): return true
            default: return false
            }
        }
        try await pair.clientProbe.waitForFinish(timeout: .seconds(5))
    }

    // MARK: - Тест 6: 4 нулевых байта → protocolViolation и закрытие

    @Test("raw zero-length frame causes protocolViolation(.invalidFrameLength(0)) and closes stream")
    func rawZeroLengthFrame() async throws {
        let harness = try await LoopbackHarness.start()
        defer { harness.stop() }

        let rawConn = harness.makeRawConnection()
        try await startRaw(rawConn)
        defer { rawConn.cancel() }

        // Ждём входящее соединение, подписываемся до start().
        let incomingEvent = try await harness.listenerProbe.waitFor(timeout: .seconds(5)) {
            if case .incoming = $0 { return true }; return false
        }
        guard case .incoming(let serverConn) = incomingEvent else {
            Issue.record("Expected .incoming event from listener"); return
        }
        let serverProbe = EventProbe<ConnectionEvent>(stream: serverConn.events)
        serverConn.start()
        _ = try await serverProbe.waitFor {
            if case .state(.ready) = $0 { return true }; return false
        }

        // 4 нулевых байта → заголовок длины = 0 → invalidFrameLength(0).
        await sendRaw(rawConn, data: Data([0, 0, 0, 0]))

        _ = try await serverProbe.waitFor(timeout: .seconds(5)) {
            if case .protocolViolation(.invalidFrameLength(0)) = $0 { return true }; return false
        }
        try await serverProbe.waitForFinish(timeout: .seconds(5))
    }

    // MARK: - Тест 7: unknownType не закрывает соединение

    @Test("unknown type frame does not close connection; next valid packet arrives")
    func unknownTypeKeepsConnectionAlive() async throws {
        let harness = try await LoopbackHarness.start()
        defer { harness.stop() }

        let rawConn = harness.makeRawConnection()
        try await startRaw(rawConn)
        defer { rawConn.cancel() }

        let incomingEvent = try await harness.listenerProbe.waitFor(timeout: .seconds(5)) {
            if case .incoming = $0 { return true }; return false
        }
        guard case .incoming(let serverConn) = incomingEvent else {
            Issue.record("Expected .incoming event from listener"); return
        }
        let serverProbe = EventProbe<ConnectionEvent>(stream: serverConn.events)
        serverConn.start()
        _ = try await serverProbe.waitFor {
            if case .state(.ready) = $0 { return true }; return false
        }

        // Отправляем кадр с неизвестным типом "typing" — соединение должно продолжить работу (§8.4).
        let typingFrame = makeRawFrame(#"{"payload":{},"type":"typing","v":1}"#)
        await sendRaw(rawConn, data: typingFrame)

        _ = try await serverProbe.waitFor(timeout: .seconds(5)) {
            if case .protocolViolation(.unknownType("typing")) = $0 { return true }; return false
        }

        // Соединение живо — отправляем валидный chatMessage.
        let msg = makeTestMsg(text: "after-typing")
        let validFrame = try PacketCodec().encodeFrame(.chatMessage(msg))
        await sendRaw(rawConn, data: validFrame)

        _ = try await serverProbe.waitFor(timeout: .seconds(5)) {
            if case .packet(.chatMessage(let m)) = $0 { return m.messageID == msg.messageID }; return false
        }

        serverConn.cancel()
    }

    // MARK: - Тест 8: send после cancel бросает NetworkError.sendFailed

    @Test("send() after cancel() throws NetworkError.sendFailed")
    func sendAfterCancel() async throws {
        let harness = try await LoopbackHarness.start()
        defer { harness.stop() }
        let pair = try await harness.connect()

        pair.client.cancel()
        try await pair.clientProbe.waitForFinish(timeout: .seconds(5))

        var threwSendFailed = false
        do {
            try await pair.client.send(.chatMessage(makeTestMsg(text: "after cancel")))
        } catch let e as NetworkError {
            if case .sendFailed = e { threwSendFailed = true }
        } catch {}
        #expect(threwSendFailed, "Expected NetworkError.sendFailed to be thrown")
    }

    // MARK: - Тест 9: перезапуск listener'а

    @Test("listener stop then start() emits new ready event and accepts client")
    func listenerRestart() async throws {
        let harness = try await LoopbackHarness.start()

        harness.stop()
        // Bonjour de-registration и завершение потока может занять несколько секунд.
        try await harness.listenerProbe.waitForFinish(timeout: .seconds(10))

        // Перезапускаем тот же BonjourHostListener.
        let serviceName = "Restart-\(UUID().uuidString.prefix(8))"
        let newStream = try harness.listener.start(serviceName: serviceName, security: .plaintext)
        let newProbe = EventProbe<ListenerEvent>(stream: newStream)
        defer { harness.listener.stop() }

        // Bonjour re-registration после перезапуска может занять > 5 с (§16.3).
        let readyEvent = try await newProbe.waitFor(timeout: .seconds(10)) {
            if case .ready = $0 { return true }; return false
        }
        guard case .ready(let newPort) = readyEvent else {
            Issue.record("Expected .ready after listener restart"); return
        }
        #expect(newPort > 0)

        // Проверяем, что новый listener принимает соединения.
        guard let nwPort = NWEndpoint.Port(rawValue: newPort) else {
            Issue.record("Invalid port after restart"); return
        }
        let client = NWPeerConnection(
            endpoint: .hostPort(host: "127.0.0.1", port: nwPort),
            parameters: .meshChat(security: .plaintext)
        )
        let clientProbe = EventProbe<ConnectionEvent>(stream: client.events)
        client.start()
        defer { client.cancel() }

        _ = try await clientProbe.waitFor(timeout: .seconds(10)) {
            if case .state(.ready) = $0 { return true }; return false
        }
    }
}

// MARK: - Хелперы

private func makeTestMsg(text: String) -> MessagePayload {
    MessagePayload(messageID: UUID(), senderID: UUID(), text: text, timestamp: Date())
}

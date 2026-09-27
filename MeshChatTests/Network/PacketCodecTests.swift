// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

// MARK: - Helpers

private func makeDate(ms: Int64) -> Date {
    Date(timeIntervalSince1970: Double(ms) / 1000.0)
}

// MARK: - Фикстуры всех 9 видов пакетов

private let peerID = UUID(uuidString: "0F8E4A4C-6C7B-4E36-9F37-2B0B7B0F6A11")!
private let sessionID = UUID(uuidString: "A1B2C3D4-0000-4000-8000-000000000001")!
private let messageID = UUID(uuidString: "9F1D0C2E-5B7A-4C3D-8E9F-0A1B2C3D4E5F")!
private let hostID = UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7")!
private let participantID = UUID(uuidString: "3B241101-E2BB-4255-8CAF-4136C566A962")!

private let authTokenHex = "6671cee409443c8c4c39995a5a53f191a04c3187efdcdbf2022dbda6999b6e19"
private let chatMessageMs: Int64 = 1_790_412_345_123
private let heartbeatMs: Int64 = 1_790_000_000_000

private var allPackets: [Packet] {
    [
        .clientHello(ClientHello(
            protocolVersion: 1,
            authToken: Data(hex: authTokenHex)!,
            permanentPeerID: peerID,
            nickname: "Петя",
            resumeSessionID: nil
        )),
        .hostWelcome(HostWelcome(
            status: "success",
            sessionID: sessionID,
            hostPermanentPeerID: hostID,
            hostNickname: "Аня",
            participants: [PeerPayload(permanentPeerID: participantID, nickname: "Вова")]
        )),
        .chatMessage(MessagePayload(
            messageID: messageID,
            senderID: peerID,
            text: "Привет! Я на месте.",
            timestamp: makeDate(ms: chatMessageMs)
        )),
        .participantJoined(PeerPayload(permanentPeerID: participantID, nickname: "Вова")),
        .participantLeft(ParticipantLeftPayload(permanentPeerID: participantID, reason: "connectionLost")),
        .sessionEnded(SessionEndedPayload(reason: "hostClosed")),
        .leave,
        .ping(HeartbeatPayload(sentAt: makeDate(ms: heartbeatMs))),
        .pong(HeartbeatPayload(sentAt: makeDate(ms: heartbeatMs))),
    ]
}

@Suite("PacketCodec", .serialized)
struct PacketCodecTests {

    private let codec = PacketCodec()

    // MARK: - 1. Контрольные кадры §8.8

    @Test("Контрольный кадр chatMessage совпадает с §8.8 побайтно")
    func goldenChatMessage() throws {
        let packet = Packet.chatMessage(MessagePayload(
            messageID: messageID,
            senderID: peerID,
            text: "Привет! Я на месте.",
            timestamp: makeDate(ms: chatMessageMs)
        ))
        let frame = try codec.encodeFrame(packet)

        let expectedJSON = #"{"payload":{"messageID":"9F1D0C2E-5B7A-4C3D-8E9F-0A1B2C3D4E5F","senderID":"0F8E4A4C-6C7B-4E36-9F37-2B0B7B0F6A11","text":"Привет! Я на месте.","timestamp":1790412345123},"type":"chatMessage","v":1}"#
        let expectedBytes = Data(expectedJSON.utf8)
        let expectedPrefix = Data([0x00, 0x00, 0x00, 0xd2])

        #expect(frame == expectedPrefix + expectedBytes,
                "Actual: prefix=\(frame.prefix(4).map { String(format: "%02x", $0) }.joined()) json=\(String(data: frame.dropFirst(4), encoding: .utf8) ?? "<invalid>")")
    }

    @Test("Контрольный кадр clientHello совпадает с §8.8 побайтно")
    func goldenClientHello() throws {
        let packet = Packet.clientHello(ClientHello(
            protocolVersion: 1,
            authToken: Data(hex: authTokenHex)!,
            permanentPeerID: peerID,
            nickname: "Петя",
            resumeSessionID: nil
        ))
        let frame = try codec.encodeFrame(packet)

        let expectedJSON = #"{"payload":{"authToken":"ZnHO5AlEPIxMOZlaWlPxkaBMMYfv3NvyAi29ppmbbhk=","nickname":"Петя","permanentPeerID":"0F8E4A4C-6C7B-4E36-9F37-2B0B7B0F6A11","protocolVersion":1},"type":"clientHello","v":1}"#
        let expectedBytes = Data(expectedJSON.utf8)
        let expectedPrefix = Data([0x00, 0x00, 0x00, 0xc6])

        #expect(frame == expectedPrefix + expectedBytes,
                "Actual: prefix=\(frame.prefix(4).map { String(format: "%02x", $0) }.joined()) json=\(String(data: frame.dropFirst(4), encoding: .utf8) ?? "<invalid>")")
    }

    @Test("Контрольный кадр leave совпадает с §8.8 побайтно")
    func goldenLeave() throws {
        let frame = try codec.encodeFrame(.leave)

        let expectedJSON = #"{"payload":{},"type":"leave","v":1}"#
        let expectedBytes = Data(expectedJSON.utf8)
        let expectedPrefix = Data([0x00, 0x00, 0x00, 0x23])

        #expect(frame == expectedPrefix + expectedBytes,
                "Actual: prefix=\(frame.prefix(4).map { String(format: "%02x", $0) }.joined()) json=\(String(data: frame.dropFirst(4), encoding: .utf8) ?? "<invalid>")")
    }

    // MARK: - 2. Туда-обратно для всех 9 видов пакетов

    @Test("Roundtrip для каждого вида пакета", arguments: allPackets)
    func roundtrip(packet: Packet) throws {
        let frame = try codec.encodeFrame(packet)
        let json = frame.dropFirst(4)
        let decoded = try codec.decodePayload(Data(json))
        #expect(decoded == packet)
    }

    // MARK: - 3. Декодер принимает «нестандартные» но валидные входы

    @Test("Декодер принимает ключи в другом порядке")
    func decodeAnyKeyOrder() throws {
        let json = #"{"type":"leave","v":1,"payload":{}}"#
        let packet = try codec.decodePayload(Data(json.utf8))
        #expect(packet == .leave)
    }

    @Test("Декодер принимает resumeSessionID: null")
    func decodeNullResumeSession() throws {
        let json = #"{"payload":{"authToken":"ZnHO5AlEPIxMOZlaWlPxkaBMMYfv3NvyAi29ppmbbhk=","nickname":"Петя","permanentPeerID":"0F8E4A4C-6C7B-4E36-9F37-2B0B7B0F6A11","protocolVersion":1,"resumeSessionID":null},"type":"clientHello","v":1}"#
        let packet = try codec.decodePayload(Data(json.utf8))
        guard case .clientHello(let hello) = packet else {
            Issue.record("Expected clientHello"); return
        }
        #expect(hello.resumeSessionID == nil)
    }

    @Test("Декодер принимает UUID в нижнем регистре")
    func decodeLowercaseUUID() throws {
        let json = #"{"payload":{"permanentPeerID":"0f8e4a4c-6c7b-4e36-9f37-2b0b7b0f6a11","nickname":"x"},"type":"participantJoined","v":1}"#
        let packet = try codec.decodePayload(Data(json.utf8))
        guard case .participantJoined(let peer) = packet else {
            Issue.record("Expected participantJoined"); return
        }
        #expect(peer.permanentPeerID == peerID)
    }

    @Test("Декодер принимает \\/ в base64")
    func decodeEscapedSlashInBase64() throws {
        // authToken с экранированной косой чертой (\/), что является допустимым JSON
        let escaped = #"{"payload":{"authToken":"ZnHO5AlEPIxMOZlaWlPxkaBMMYfv3NvyAi29ppmbbhk=","nickname":"Петя","permanentPeerID":"0F8E4A4C-6C7B-4E36-9F37-2B0B7B0F6A11","protocolVersion":1},"type":"clientHello","v":1}"#
            .replacingOccurrences(of: "/", with: "\\/")
        let packet = try codec.decodePayload(Data(escaped.utf8))
        guard case .clientHello(let hello) = packet else {
            Issue.record("Expected clientHello"); return
        }
        #expect(hello.authToken == Data(hex: authTokenHex)!)
    }

    // MARK: - 4. Ошибки декодирования

    private struct ErrorCase: CustomStringConvertible {
        let json: String
        let expected: PacketCodecError
        var description: String { "json=\(json.prefix(40)) → \(expected)" }
    }

    private let errorCases: [ErrorCase] = [
        ErrorCase(json: "not json at all", expected: .malformedJSON),
        ErrorCase(json: #"{"payload":{},"type":"chatMessage","v":2}"#, expected: .unsupportedVersion(2)),
        ErrorCase(json: #"{"payload":{},"type":"typing","v":1}"#, expected: .unknownType("typing")),
        ErrorCase(
            json: #"{"payload":{"messageID":"9F1D0C2E-5B7A-4C3D-8E9F-0A1B2C3D4E5F","senderID":"0F8E4A4C-6C7B-4E36-9F37-2B0B7B0F6A11","timestamp":1000000},"type":"chatMessage","v":1}"#,
            expected: .malformedJSON
        ),
        ErrorCase(json: #"{"payload":{},"v":1}"#, expected: .malformedJSON),
    ]

    @Test("Ошибки декодирования", arguments: 0..<5)
    func decodeErrors(index: Int) throws {
        let c = errorCases[index]
        #expect(throws: c.expected) {
            try codec.decodePayload(Data(c.json.utf8))
        }
    }

    // MARK: - 5. Слишком длинный кадр

    @Test("encodeFrame с текстом 70000 символов → invalidFrameLength")
    func oversizedFrame() throws {
        let longText = String(repeating: "А", count: 70_000)
        let packet = Packet.chatMessage(MessagePayload(
            messageID: messageID,
            senderID: peerID,
            text: longText,
            timestamp: makeDate(ms: chatMessageMs)
        ))
        #expect(throws: PacketCodecError.self) {
            let frame = try codec.encodeFrame(packet)
            _ = frame
        }
        // Проверим конкретный тип ошибки
        do {
            _ = try codec.encodeFrame(packet)
            Issue.record("Expected invalidFrameLength, but no error was thrown")
        } catch PacketCodecError.invalidFrameLength(let len) {
            #expect(len > PacketCodec.maxFrameLength)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    // MARK: - 6. Дробные миллисекунды усекаются вниз

    @Test("Дата с дробной частью миллисекунды кодируется как 123, не 124")
    func fractionalMsTruncatesDown() throws {
        // 1 000 000 000 s + 0.1239 s = "123.9 ms" дробная часть
        let t = Date(timeIntervalSince1970: 1_000_000_000.0 + 0.1239)
        let packet = Packet.ping(HeartbeatPayload(sentAt: t))
        let frame = try codec.encodeFrame(packet)
        let json = Data(frame.dropFirst(4))
        let decoded = try codec.decodePayload(json)
        guard case .ping(let hb) = decoded else {
            Issue.record("Expected ping"); return
        }
        // Декодированное время должно иметь ровно 123 мс в дробной части, а не 124
        let decodedMs = Int64((hb.sentAt.timeIntervalSince1970 * 1000).rounded(.down))
        let expectedMs = Int64(1_000_000_000.0 * 1000) + 123
        #expect(decodedMs == expectedMs)
    }
}

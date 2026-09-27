// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Кодирует/декодирует пакеты протокола MeshChat (§8.1, §8.2, §8.6).
///
/// Конверт: `{"payload":…,"type":…,"v":1}` (ключи в алфавитном порядке).
/// Кадр: 4 байта длины big-endian + UTF-8 JSON.
nonisolated struct PacketCodec: Sendable {

    /// Поддерживаемая версия протокола.
    static let protocolVersion = 1
    
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    nonisolated init() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            // Целые миллисекунды, округление вниз (§8.2).
            let ms = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
            try c.encode(ms)
        }
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let ms = try c.decode(Int64.self)
            return Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        self.decoder = dec
    }

    // MARK: - Encoding

    /// Кодирует пакет в кадр с 4-байтовым big-endian префиксом длины.
    ///
    /// Бросает `PacketCodecError.invalidFrameLength`, если JSON превышает `maxFrameLength`.
    nonisolated func encodeFrame(_ packet: Packet) throws -> Data {
        let json = try encodeToJSON(packet)
        let byteCount = json.count
        guard byteCount <= FrameAssembler.maxFrameLength else {
            throw PacketCodecError.invalidFrameLength(byteCount)
        }
        var frame = Data(capacity: 4 + byteCount)
        let length = UInt32(byteCount)
        frame.append(UInt8((length >> 24) & 0xFF))
        frame.append(UInt8((length >> 16) & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(UInt8(length & 0xFF))
        frame.append(contentsOf: json)
        return frame
    }

    // MARK: - Decoding

    /// Декодирует пакет из JSON-тела кадра (без префикса длины).
    ///
    /// Порядок ошибок: `malformedJSON` → `unsupportedVersion` → `unknownType` → `malformedJSON` (§8.6).
    nonisolated func decodePayload(_ json: Data) throws -> Packet {
        // Фаза 1 — разобрать конверт через JSONSerialization
        guard
            let obj = (try? JSONSerialization.jsonObject(with: json, options: [])) as? [String: Any],
            let v = obj["v"] as? Int,
            let typeStr = obj["type"] as? String
        else {
            throw PacketCodecError.malformedJSON
        }

        // Фаза 2 — проверить версию
        guard v == PacketCodec.protocolVersion else {
            throw PacketCodecError.unsupportedVersion(v)
        }

        // Фаза 3 — проверить тип
        guard let packetType = PacketType(rawValue: typeStr) else {
            throw PacketCodecError.unknownType(typeStr)
        }

        // Фаза 4 — декодировать payload
        guard
            let payloadAny = obj["payload"],
            let payloadData = try? JSONSerialization.data(withJSONObject: payloadAny)
        else {
            throw PacketCodecError.malformedJSON
        }

        do {
            switch packetType {
            case .clientHello:
                return .clientHello(try decoder.decode(ClientHello.self, from: payloadData))
            case .hostWelcome:
                return .hostWelcome(try decoder.decode(HostWelcome.self, from: payloadData))
            case .chatMessage:
                return .chatMessage(try decoder.decode(MessagePayload.self, from: payloadData))
            case .participantJoined:
                return .participantJoined(try decoder.decode(PeerPayload.self, from: payloadData))
            case .participantLeft:
                return .participantLeft(try decoder.decode(ParticipantLeftPayload.self, from: payloadData))
            case .sessionEnded:
                return .sessionEnded(try decoder.decode(SessionEndedPayload.self, from: payloadData))
            case .leave:
                return .leave
            case .ping:
                return .ping(try decoder.decode(HeartbeatPayload.self, from: payloadData))
            case .pong:
                return .pong(try decoder.decode(HeartbeatPayload.self, from: payloadData))
            }
        } catch {
            throw PacketCodecError.malformedJSON
        }
    }

    // MARK: - Private helpers

    private nonisolated struct EmptyPayload: Encodable {}

    private nonisolated struct OutgoingEnvelope<P: Encodable>: Encodable {
        let type: String
        let payload: P

        enum CodingKeys: String, CodingKey { case payload, type, v }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(payload, forKey: .payload)
            try c.encode(type, forKey: .type)
            try c.encode(PacketCodec.protocolVersion, forKey: .v)
        }
    }

    private nonisolated func encodeToJSON(_ packet: Packet) throws -> Data {
        switch packet {
        case .clientHello(let p):
            return try encoder.encode(OutgoingEnvelope(type: PacketType.clientHello.rawValue, payload: p))
        case .hostWelcome(let p):
            return try encoder.encode(OutgoingEnvelope(type: PacketType.hostWelcome.rawValue, payload: p))
        case .chatMessage(let p):
            return try encoder.encode(OutgoingEnvelope(type: PacketType.chatMessage.rawValue, payload: p))
        case .participantJoined(let p):
            return try encoder.encode(OutgoingEnvelope(type: PacketType.participantJoined.rawValue, payload: p))
        case .participantLeft(let p):
            return try encoder.encode(OutgoingEnvelope(type: PacketType.participantLeft.rawValue, payload: p))
        case .sessionEnded(let p):
            return try encoder.encode(OutgoingEnvelope(type: PacketType.sessionEnded.rawValue, payload: p))
        case .leave:
            return try encoder.encode(OutgoingEnvelope(type: PacketType.leave.rawValue, payload: EmptyPayload()))
        case .ping(let p):
            return try encoder.encode(OutgoingEnvelope(type: PacketType.ping.rawValue, payload: p))
        case .pong(let p):
            return try encoder.encode(OutgoingEnvelope(type: PacketType.pong.rawValue, payload: p))
        }
    }
}

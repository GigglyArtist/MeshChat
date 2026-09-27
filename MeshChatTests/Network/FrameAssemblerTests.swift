// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

@Suite("FrameAssembler")
struct FrameAssemblerTests {

    private let codec = PacketCodec()

    // MARK: - Helpers

    private func makeFrame(_ packet: Packet) throws -> Data {
        try codec.encodeFrame(packet)
    }

    private func samplePacket(index: Int = 0) -> Packet {
        let id = UUID()
        switch index % 3 {
        case 0: return .ping(HeartbeatPayload(sentAt: Date(timeIntervalSince1970: Double(index) * 1000)))
        case 1: return .leave
        default: return .participantJoined(PeerPayload(permanentPeerID: id, nickname: "User\(index)"))
        }
    }

    // MARK: - Тест 1: один кадр в одном чанке

    @Test("Один кадр, один чанк")
    func oneFrameOneChunk() throws {
        let frame = try makeFrame(.leave)
        var assembler = FrameAssembler()
        let frames = try assembler.append(frame)
        #expect(frames.count == 1)
        let decoded = try codec.decodePayload(frames[0])
        #expect(decoded == .leave)
    }

    // MARK: - Тест 2: кадр побайтно

    @Test("Кадр приходит побайтно")
    func frameByteByByte() throws {
        let frame = try makeFrame(.leave)
        var assembler = FrameAssembler()
        var collected: [Data] = []
        for byte in frame {
            let result = try assembler.append(Data([byte]))
            collected.append(contentsOf: result)
        }
        #expect(collected.count == 1)
        let decoded = try codec.decodePayload(collected[0])
        #expect(decoded == .leave)
    }

    // MARK: - Тест 3: два кадра в одном чанке

    @Test("Два кадра в одном чанке")
    func twoFramesOneChunk() throws {
        let packet1 = Packet.leave
        let packet2 = Packet.ping(HeartbeatPayload(sentAt: Date(timeIntervalSince1970: 1_000_000)))
        let combined = try makeFrame(packet1) + makeFrame(packet2)
        var assembler = FrameAssembler()
        let frames = try assembler.append(combined)
        #expect(frames.count == 2)
        #expect(try codec.decodePayload(frames[0]) == packet1)
        #expect(try codec.decodePayload(frames[1]) == packet2)
    }

    // MARK: - Тест 4: заголовок разбит на 2+2 байта

    @Test("Заголовок разбит 2+2 байта")
    func headerSplit2Plus2() throws {
        let frame = try makeFrame(.leave)
        var assembler = FrameAssembler()
        let part1 = frame.prefix(2)
        let part2 = frame.dropFirst(2)
        let r1 = try assembler.append(Data(part1))
        #expect(r1.isEmpty)
        let r2 = try assembler.append(Data(part2))
        #expect(r2.count == 1)
        #expect(try codec.decodePayload(r2[0]) == .leave)
    }

    // MARK: - Тест 5: полтора кадра

    @Test("Полтора кадра в двух чанках")
    func oneAndHalfFrames() throws {
        let packet1 = Packet.leave
        let packet2 = Packet.ping(HeartbeatPayload(sentAt: Date(timeIntervalSince1970: 2_000_000)))
        let frame1 = try makeFrame(packet1)
        let frame2 = try makeFrame(packet2)

        // Первый чанк: весь frame1 + половина frame2
        let half = frame2.count / 2
        let chunk1 = frame1 + frame2.prefix(half)
        let chunk2 = frame2.dropFirst(half)

        var assembler = FrameAssembler()
        let r1 = try assembler.append(Data(chunk1))
        #expect(r1.count == 1)
        #expect(try codec.decodePayload(r1[0]) == packet1)

        let r2 = try assembler.append(Data(chunk2))
        #expect(r2.count == 1)
        #expect(try codec.decodePayload(r2[0]) == packet2)
    }

    // MARK: - Тест 6: невалидная длина

    @Test("Длина 0 в заголовке → invalidFrameLength(0)")
    func zeroLength() throws {
        let badFrame = Data([0x00, 0x00, 0x00, 0x00])
        var assembler = FrameAssembler()
        #expect(throws: PacketCodecError.invalidFrameLength(0)) {
            try assembler.append(badFrame)
        }
    }

    @Test("Длина 65537 в заголовке → invalidFrameLength(65537)")
    func oversizedLength() throws {
        // 65537 = 0x00010001
        let badFrame = Data([0x00, 0x01, 0x00, 0x01])
        var assembler = FrameAssembler()
        #expect(throws: PacketCodecError.invalidFrameLength(65537)) {
            try assembler.append(badFrame)
        }
    }

    // MARK: - Тест 7: возвращённые Data начинаются с startIndex == 0

    @Test("Возвращённые Data начинаются с startIndex 0 даже если входной чанк — срез")
    func sliceStartIndex() throws {
        let frame = try makeFrame(.leave)
        // Создаём срез с ненулевым startIndex
        let padded = Data([0xFF, 0xFF]) + frame
        let slice = padded[2...] // startIndex == 2
        #expect(slice.startIndex == 2)

        var assembler = FrameAssembler()
        let frames = try assembler.append(slice)
        #expect(frames.count == 1)
        #expect(frames[0].startIndex == 0)
        #expect(try codec.decodePayload(frames[0]) == .leave)
    }

    // MARK: - Тест 8: стресс-тест — 200 кадров, случайные чанки

    @Test("Стресс: 200 кадров, случайные чанки 1–300 байт")
    func stressRandomChunks() throws {
        // Формируем 200 пакетов и кодируем их в один поток байт
        let packets: [Packet] = (0..<200).map { samplePacket(index: $0) }
        let stream: Data = try packets.reduce(Data()) { acc, p in acc + (try codec.encodeFrame(p)) }

        // Нарезаем поток на случайные чанки размером 1–300 байт
        var rng = SeededGenerator(seed: 0xDEAD_BEEF_1234_5678)
        var pos = 0
        var assembler = FrameAssembler()
        var decoded: [Packet] = []

        while pos < stream.count {
            let maxChunk = min(300, stream.count - pos)
            let chunkSize = Int(rng.next() % UInt64(maxChunk)) + 1
            let end = pos + chunkSize
            let chunk = stream[pos..<end]
            let frames = try assembler.append(chunk)
            for f in frames {
                decoded.append(try codec.decodePayload(f))
            }
            pos = end
        }

        #expect(decoded.count == packets.count)
        #expect(decoded == packets)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

@Suite("PacketPayload domain mapping")
struct PacketPayloadMappingTests {

    // MARK: - PeerPayload ↔ PeerProfile

    @Test("PeerProfile → PeerPayload → PeerProfile без потерь")
    func peerProfileRoundtrip() {
        let profile = PeerProfile(id: UUID(), nickname: "Аня")
        let dto = PeerPayload(profile)
        let restored = dto.profile
        #expect(restored == profile)
    }

    // MARK: - MessagePayload ↔ ChatMessage

    @Test("ChatMessage → MessagePayload → ChatMessage без потерь")
    func chatMessageRoundtrip() {
        let ms: Int64 = 1_790_412_345_000
        let message = ChatMessage(
            id: UUID(),
            text: "Привет! 🎉",
            timestamp: Date(timeIntervalSince1970: Double(ms) / 1000.0),
            senderID: UUID()
        )
        let dto = MessagePayload(message)
        let restored = dto.message
        #expect(restored == message)
    }

    // MARK: - ParticipantLeftPayload ↔ LeaveReason

    @Test("LeaveReason.left туда-обратно")
    func leaveReasonLeft() {
        let peerID = UUID()
        let dto = ParticipantLeftPayload(peerID: peerID, reason: .left)
        #expect(dto.permanentPeerID == peerID)
        #expect(dto.leaveReason == .left)
    }

    @Test("LeaveReason.connectionLost туда-обратно")
    func leaveReasonConnectionLost() {
        let peerID = UUID()
        let dto = ParticipantLeftPayload(peerID: peerID, reason: .connectionLost)
        #expect(dto.permanentPeerID == peerID)
        #expect(dto.leaveReason == .connectionLost)
    }

    @Test("Неизвестная причина трактуется как .connectionLost")
    func unknownReasonFallback() {
        let dto = ParticipantLeftPayload(permanentPeerID: UUID(), reason: "typing")
        #expect(dto.leaveReason == .connectionLost)
    }
}

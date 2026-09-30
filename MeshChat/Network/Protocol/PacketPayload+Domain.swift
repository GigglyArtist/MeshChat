// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

// MARK: - PeerPayload ↔ PeerProfile

nonisolated extension PeerPayload {
    /// Инициализирует DTO из доменной модели участника.
    nonisolated init(_ profile: PeerProfile) {
        self.init(permanentPeerID: profile.id, nickname: profile.nickname)
    }

    /// Переводит DTO в доменную модель участника.
    nonisolated var profile: PeerProfile {
        PeerProfile(id: permanentPeerID, nickname: nickname)
    }
}

// MARK: - MessagePayload ↔ ChatMessage

nonisolated extension MessagePayload {
    /// Инициализирует DTO из доменного сообщения.
    nonisolated init(_ message: ChatMessage) {
        self.init(
            messageID: message.id,
            senderID: message.senderID,
            text: message.text,
            timestamp: message.timestamp
        )
    }

    /// Переводит DTO в доменное сообщение.
    nonisolated var message: ChatMessage {
        ChatMessage(id: messageID, text: text, timestamp: timestamp, senderID: senderID)
    }
}

// MARK: - ParticipantLeftPayload ↔ LeaveReason

nonisolated extension ParticipantLeftPayload {
    /// Инициализирует DTO с указанием причины в виде доменного типа.
    nonisolated init(peerID: UUID, reason: LeaveReason) {
        self.init(permanentPeerID: peerID, reason: reason.rawValue)
    }

    /// Возвращает причину ухода; неизвестная строка трактуется как `.connectionLost` (§8.6).
    nonisolated var leaveReason: LeaveReason {
        LeaveReason(rawValue: reason) ?? .connectionLost
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

#if DEBUG
import Foundation

/// Реализация `HistoryServicing` для SwiftUI Previews (§12.2, §13).
///
/// Три собеседника: у одного две сессии с сообщениями в обе стороны,
/// у другого — одна сессия, у третьего — ни одной.
nonisolated struct PreviewHistoryService: HistoryServicing {

    // MARK: - Preview data

    private static let localPeerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private static let peerAnya  = PeerProfile(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!, nickname: "Аня")
    private static let peerVova  = PeerProfile(id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!, nickname: "Вова")
    private static let peerRita  = PeerProfile(id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!, nickname: "Рита")

    private static let session1ID = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
    private static let session2ID = UUID(uuidString: "22222222-0000-0000-0000-000000000001")!
    private static let session3ID = UUID(uuidString: "33333333-0000-0000-0000-000000000001")!

    private static let t1 = Date(timeIntervalSince1970: 1_700_000_000)
    private static let t2 = Date(timeIntervalSince1970: 1_700_100_000)
    private static let t3 = Date(timeIntervalSince1970: 1_700_200_000)

    private static let session1 = ChatSessionInfo(
        id: session1ID,
        createdAt: t1,
        endedAt: Date(timeIntervalSince1970: 1_700_003_600),
        role: .host,
        participants: [peerAnya, peerVova]
    )

    private static let session2 = ChatSessionInfo(
        id: session2ID,
        createdAt: t2,
        endedAt: Date(timeIntervalSince1970: 1_700_103_600),
        role: .client,
        participants: [peerAnya]
    )

    private static let session3 = ChatSessionInfo(
        id: session3ID,
        createdAt: t3,
        endedAt: nil,
        role: .host,
        participants: [peerVova]
    )

    // nonisolated(unsafe): Data является Sendable-типом, но статические свойства
    // могут вызвать предупреждение только если они изменяемые — здесь let, поэтому
    // использование static let корректно; структуры Sendable.
    private static let messages1: [ChatMessage] = [
        ChatMessage(id: UUID(), text: "Привет! Как дела?",
                    timestamp: Date(timeIntervalSince1970: 1_700_000_100).flooredToMilliseconds,
                    senderID: localPeerID),
        ChatMessage(id: UUID(), text: "Всё отлично, спасибо!",
                    timestamp: Date(timeIntervalSince1970: 1_700_000_200).flooredToMilliseconds,
                    senderID: peerAnya.id),
        ChatMessage(id: UUID(), text: "Когда встретимся?",
                    timestamp: Date(timeIntervalSince1970: 1_700_000_300).flooredToMilliseconds,
                    senderID: localPeerID),
        ChatMessage(id: UUID(), text: "Завтра в 18:00 подойдёт?",
                    timestamp: Date(timeIntervalSince1970: 1_700_000_400).flooredToMilliseconds,
                    senderID: peerAnya.id)
    ]

    private static let messages2: [ChatMessage] = [
        ChatMessage(id: UUID(), text: "Ты уже дома?",
                    timestamp: Date(timeIntervalSince1970: 1_700_100_100).flooredToMilliseconds,
                    senderID: peerAnya.id),
        ChatMessage(id: UUID(), text: "Да, только пришёл",
                    timestamp: Date(timeIntervalSince1970: 1_700_100_200).flooredToMilliseconds,
                    senderID: localPeerID)
    ]

    private static let messages3: [ChatMessage] = [
        ChatMessage(id: UUID(), text: "Вова, как слышно?",
                    timestamp: Date(timeIntervalSince1970: 1_700_200_100).flooredToMilliseconds,
                    senderID: localPeerID),
        ChatMessage(id: UUID(), text: "Слышу хорошо!",
                    timestamp: Date(timeIntervalSince1970: 1_700_200_200).flooredToMilliseconds,
                    senderID: peerVova.id)
    ]

    // MARK: - HistoryServicing

    nonisolated func peerSummaries() async throws -> [PeerSummary] {
        [
            PeerSummary(profile: Self.peerAnya, sessionCount: 2, lastSessionAt: Self.t2),
            PeerSummary(profile: Self.peerVova, sessionCount: 1, lastSessionAt: Self.t3),
            PeerSummary(profile: Self.peerRita, sessionCount: 0, lastSessionAt: nil)
        ]
    }

    nonisolated func sessions(withPeer peerID: UUID) async throws -> [ChatSessionInfo] {
        if peerID == Self.peerAnya.id { return [Self.session2, Self.session1] }
        if peerID == Self.peerVova.id { return [Self.session3] }
        return []
    }

    nonisolated func transcript(sessionID: UUID) async throws -> SessionTranscript {
        switch sessionID {
        case Self.session1ID: return SessionTranscript(session: Self.session1, messages: Self.messages1)
        case Self.session2ID: return SessionTranscript(session: Self.session2, messages: Self.messages2)
        case Self.session3ID: return SessionTranscript(session: Self.session3, messages: Self.messages3)
        default: throw StorageError.sessionNotFound(sessionID)
        }
    }

    nonisolated func deleteSession(id: UUID) async throws {
        // Preview: удаление ничего не делает
    }
}
#endif

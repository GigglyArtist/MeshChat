// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Чистые функции форматирования для экранов истории (§12.1.2).
enum HistoryFormatting {

    /// Подпись под ником в списке собеседников.
    /// «3 чата · 4 окт.» или «Нет сохранённых чатов».
    nonisolated static func peerSubtitle(_ summary: PeerSummary) -> String {
        guard summary.sessionCount > 0, let date = summary.lastSessionAt else {
            return "Нет сохранённых чатов"
        }
        let word = RussianPlural.word(for: summary.sessionCount, one: "чат", few: "чата", many: "чатов")
        let dateStr = date.formatted(.dateTime.day().month(.abbreviated))
        return "\(summary.sessionCount) \(word) · \(dateStr)"
    }

    /// Заголовок строки сессии: дата и время начала.
    nonisolated static func sessionTitle(_ session: ChatSessionInfo) -> String {
        session.createdAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }

    /// Подпись строки сессии: роль и участники по нику в алфавитном порядке.
    nonisolated static func sessionSubtitle(_ session: ChatSessionInfo) -> String {
        let roleStr = session.role == .host ? "Вы были хостом" : "Вы были участником"
        let sorted = session.participants.sorted {
            $0.nickname.localizedStandardCompare($1.nickname) == .orderedAscending
        }
        guard !sorted.isEmpty else { return roleStr }
        let names = sorted.map(\.nickname).joined(separator: ", ")
        return "\(roleStr) · \(names)"
    }
}

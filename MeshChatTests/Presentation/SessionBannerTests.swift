// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

@MainActor
@Suite("SessionBanner")
struct SessionBannerTests {

    // MARK: - Параметризованный тест (§12.3)

    @Test("text(for:) по таблице §12.3", arguments: zip(
        [
            SessionState.connecting,
            SessionState.active,
            SessionState.ended(.hostEnded),
            SessionState.ended(.hostLost),
            SessionState.ended(.rejected),
            SessionState.ended(.hostUnreachable),
            SessionState.ended(.handshakeTimeout),
            SessionState.ended(.localNetworkDenied),
            SessionState.ended(.leftByUser),
            SessionState.ended(.failed("oops")),
        ],
        [
            Optional("Подключение…"),
            Optional<String>.none,
            Optional("Хост завершил сессию"),
            Optional("Хост завершил сессию"),
            Optional("Не удалось войти: неверный QR-код или комната заполнена"),
            Optional("Не удалось подключиться: убедитесь, что хост рядом и QR-код актуален"),
            Optional("Не удалось подключиться: убедитесь, что хост рядом и QR-код актуален"),
            Optional("Разрешите доступ к локальной сети: Настройки → MeshChat"),
            Optional<String>.none,
            Optional("Ошибка: oops"),
        ]
    ))
    func bannerText(state: SessionState, expected: String?) {
        #expect(SessionBanner.text(for: state) == expected)
    }

    // MARK: - Обратный отсчёт reconnecting

    @Test("reconnecting — показывает оставшиеся секунды")
    func reconnectingShowsCountdown() {
        let now = Date(timeIntervalSince1970: 1000)
        let deadline = Date(timeIntervalSince1970: 1030)   // 30 с вперёд
        let text = SessionBanner.text(for: .reconnecting(deadline: deadline), now: now)
        #expect(text == "Связь потеряна. Переподключение… 30 с")
    }

    @Test("reconnecting с истёкшим дедлайном — 0 с")
    func reconnectingExpiredShowsZero() {
        let now = Date(timeIntervalSince1970: 1000)
        let deadline = Date(timeIntervalSince1970: 990)    // дедлайн в прошлом
        let text = SessionBanner.text(for: .reconnecting(deadline: deadline), now: now)
        #expect(text == "Связь потеряна. Переподключение… 0 с")
    }
}

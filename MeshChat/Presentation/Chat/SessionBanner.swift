// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Баннер состояния сессии: чистая функция `SessionState → текст` (§12.3).
///
/// `nil` — баннер скрыт (состояние `.active` и `.ended(.leftByUser)`).
/// Для `.reconnecting` состояния View использует `TimelineView` для обратного отсчёта.
struct SessionBanner: View {

    let state: SessionState

    var body: some View {
        switch state {
        case .connecting:
            bannerText("Подключение…")
        case .active:
            EmptyView()
        case .reconnecting(let deadline):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(deadline.timeIntervalSince(context.date)))
                bannerText("Связь потеряна. Переподключение… \(seconds) с")
            }
        case .ended(let reason):
            if let text = Self.endedText(reason) {
                bannerText(text)
            }
        }
    }

    private func bannerText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
    }

    // MARK: - Чистая функция состояния → строка (§12.3)

    /// Текст баннера для данного состояния. `nil` — баннер скрыт.
    /// `now` используется для вычисления оставшихся секунд в `.reconnecting`.
    static func text(for state: SessionState, now: Date = Date()) -> String? {
        switch state {
        case .connecting:
            return "Подключение…"
        case .active:
            return nil
        case .reconnecting(let deadline):
            let seconds = max(0, Int(deadline.timeIntervalSince(now)))
            return "Связь потеряна. Переподключение… \(seconds) с"
        case .ended(let reason):
            return endedText(reason)
        }
    }

    private static func endedText(_ reason: SessionEndReason) -> String? {
        switch reason {
        case .leftByUser:
            return nil
        case .hostEnded, .hostLost:
            return "Хост завершил сессию"
        case .rejected:
            return "Не удалось войти: неверный QR-код или комната заполнена"
        case .hostUnreachable, .handshakeTimeout:
            return "Не удалось подключиться: убедитесь, что хост рядом и QR-код актуален"
        case .localNetworkDenied:
            return "Разрешите доступ к локальной сети: Настройки → MeshChat"
        case .failed(let msg):
            return "Ошибка: \(msg)"
        }
    }
}

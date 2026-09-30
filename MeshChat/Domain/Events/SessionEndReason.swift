// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Причина завершения сессии (§5.1).
nonisolated enum SessionEndReason: Sendable, Equatable {
    /// Пользователь вышел сам.
    case leftByUser
    /// Хост завершил комнату.
    case hostEnded
    /// Связь с хостом потеряна без восстановления.
    case hostLost
    /// Хост отклонил вход (неверный токен, переполнение).
    case rejected
    /// Не удалось подключиться за `connectTimeout`.
    case hostUnreachable
    /// Хэндшейк не завершился за `handshakeTimeout`.
    case handshakeTimeout
    /// Нет разрешения «Локальная сеть».
    case localNetworkDenied
    /// Иная неустранимая ошибка.
    case failed(String)
}

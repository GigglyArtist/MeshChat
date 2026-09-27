// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Секрет комнаты. Живёт только в памяти, никогда не пишется на диск и в логи (§6.3).
protocol RoomSecret: Sendable {
    /// 32 байта ключа комнаты — передаётся в QR-приглашении.
    var roomKeyData: Data { get }

    /// Производный ключ для TLS-PSK канала.
    var tlsPreSharedKey: Data { get }

    /// Токен аутентификации для указанного участника.
    func authToken(for peerID: UUID) -> Data

    /// Проверяет токен за постоянное время. Никогда не использует `==`.
    func isValidAuthToken(_ token: Data, for peerID: UUID) -> Bool
}

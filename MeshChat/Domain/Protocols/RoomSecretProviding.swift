// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Фабрика секретов комнаты (§6.3). Реализация в Security/, протокол в Domain/.
protocol RoomSecretProviding: Sendable {
    /// Хост: генерирует случайную соль и выводит ключ из пароля.
    nonisolated func makeSecret(password: String) -> any RoomSecret

    /// Клиент: восстанавливает секрет из QR-приглашения.
    /// Бросает `InviteError.invalidKey`, если ключ не 32 байта.
    nonisolated func secret(from invite: RoomInvite) throws -> any RoomSecret
}

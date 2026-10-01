// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Фабрика активных комнат: создаёт или присоединяется к комнате (§11).
///
/// Все требования `nonisolated`: протокол объявлен вне Presentation/App.
protocol RoomServicing: Sendable {

    /// Создаёт комнату как хост: выводит ключи из `password`, запускает сессию.
    ///
    /// - Throws: `RoomError.nicknameMissing` если ник не задан.
    nonisolated func createRoom(password: String) async throws -> any ActiveRoomHandling

    /// Присоединяется к комнате как клиент через `invite`.
    ///
    /// - Throws: `RoomError.nicknameMissing` если ник не задан.
    nonisolated func joinRoom(invite: RoomInvite) async throws -> any ActiveRoomHandling
}

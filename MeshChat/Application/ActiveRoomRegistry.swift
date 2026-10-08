// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import os

/// Хранит ссылку на единственную активную комнату устройства (ADR-13, §11.2).
///
/// Гарантирует: перед созданием новой сессии предыдущая комната покинута.
/// Ссылка обнуляется **до** `await room.leave()`: при реентерабельности актора
/// повторные вызовы `leaveCurrent()` уже не найдут эту комнату.
actor ActiveRoomRegistry {

    private var current: (any ActiveRoomHandling)?

    private nonisolated static let logger = Logger(
        subsystem: "com.meshchat", category: "ActiveRoomRegistry"
    )

    nonisolated init() {}

    /// Покидает текущую комнату, если она есть.
    func leaveCurrent() async {
        guard let room = current else { return }
        current = nil
        Self.logger.info("leaveCurrent: leaving previous room before new session")
        await room.leave()
    }

    /// Устанавливает новую текущую комнату.
    ///
    /// Если уже зарегистрирован другой объект (`!==`), покидает его.
    func setCurrent(_ room: any ActiveRoomHandling) async {
        guard let existing = current, existing !== room else {
            current = room
            return
        }
        current = room
        await existing.leave()
    }
}

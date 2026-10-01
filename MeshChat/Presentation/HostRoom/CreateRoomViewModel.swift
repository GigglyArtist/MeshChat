// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.meshchat", category: "ui")

/// ViewModel экрана создания комнаты (§12.1).
@Observable @MainActor final class CreateRoomViewModel {

    enum State {
        case editing
        case loading
        case failed(String)
    }

    var passwordInput: String = ""
    private(set) var state: State = .editing
    /// Установлена после успешного `createRoom`; View наблюдает и вызывает `onSuccess`.
    private(set) var createdRoom: (any ActiveRoomHandling)?

    private let rooms: any RoomServicing

    var canCreate: Bool {
        guard case .editing = state else { return false }
        return RoomPasswordPolicy.isValid(passwordInput)
    }

    init(rooms: any RoomServicing) {
        self.rooms = rooms
    }

    func createRoom() async {
        guard canCreate else { return }
        state = .loading
        let password = passwordInput
        // Очищаем пароль сразу — §6.3
        passwordInput = ""
        do {
            let room = try await rooms.createRoom(password: password)
            createdRoom = room
        } catch RoomError.nicknameMissing {
            state = .failed("Укажите ник перед созданием комнаты")
        } catch {
            logger.error("createRoom failed: \(error, privacy: .public)")
            state = .failed("Не удалось создать комнату")
        }
    }
}

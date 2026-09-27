// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// ViewModel экрана создания комнаты (§12.1).
@Observable @MainActor final class CreateRoomViewModel {

    enum State {
        case editing
        case ready(invite: RoomInvite)
        case failed(String)
    }

    var passwordInput: String = ""
    private(set) var state: State = .editing

    private let secrets: any RoomSecretProviding
    private let serviceName: String

    var canCreate: Bool { RoomPasswordPolicy.isValid(passwordInput) }

    init(secrets: any RoomSecretProviding, peerID: UUID) {
        self.secrets = secrets
        self.serviceName = peerID.uuidString
    }

    func createRoom() {
        guard canCreate else { return }
        let secret = secrets.makeSecret(password: passwordInput)
        let invite = RoomInvite(
            version: RoomInvite.currentVersion,
            serviceName: serviceName,
            roomKey: secret.roomKeyData
        )
        // Очищаем пароль сразу после использования — §6.3
        passwordInput = ""
        state = .ready(invite: invite)
    }
}

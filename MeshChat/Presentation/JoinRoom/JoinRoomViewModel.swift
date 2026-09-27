// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// ViewModel экрана входа в комнату по QR (§12.1).
@Observable @MainActor final class JoinRoomViewModel {

    enum State {
        case checkingCamera
        case scanning
        case cameraDenied
        case found(invite: RoomInvite)
        case failed(String)
    }

    private(set) var state: State = .checkingCamera

    #if DEBUG
    var debugPayloadInput: String = ""
    #endif

    private let secrets: any RoomSecretProviding

    init(secrets: any RoomSecretProviding) {
        self.secrets = secrets
    }

    func prepare() async {
        switch CameraPermission.current() {
        case .granted:
            state = .scanning
        case .denied:
            state = .cameraDenied
        case .notDetermined:
            let result = await CameraPermission.request()
            state = result == .granted ? .scanning : .cameraDenied
        }
    }

    func handleScan(_ payload: String) {
        guard case .scanning = state else { return }
        do {
            let invite = try RoomInvite.parse(qrPayload: payload)
            _ = try secrets.secret(from: invite)
            state = .found(invite: invite)
        } catch InviteError.unsupportedVersion(let v) {
            state = .failed("Неподдерживаемая версия приглашения (\(v)).")
        } catch {
            // notMeshChatCode, invalidKey — не MeshChat QR, продолжаем сканировать
            return
        }
    }

    #if DEBUG
    func handleDebugPaste() {
        handleScan(debugPayloadInput)
    }
    #endif
}

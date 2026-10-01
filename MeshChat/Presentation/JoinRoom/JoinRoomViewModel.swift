// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.meshchat", category: "ui")

/// ViewModel экрана входа в комнату по QR (§12.1).
@Observable @MainActor final class JoinRoomViewModel {

    enum State {
        case checkingCamera
        case scanning
        case cameraDenied
        case joining
        case failed(String)
    }

    private(set) var state: State = .checkingCamera
    /// Установлена после успешного `joinRoom`; View наблюдает и вызывает `onSuccess`.
    private(set) var joinedRoom: (any ActiveRoomHandling)?

    #if DEBUG
    var debugPayloadInput: String = ""
    #endif

    private let rooms: any RoomServicing
    private let checkCamera: () -> CameraPermission
    private let requestCamera: () async -> CameraPermission

    init(
        rooms: any RoomServicing,
        checkCamera: @escaping () -> CameraPermission = { CameraPermission.current() },
        requestCamera: @escaping () async -> CameraPermission = { await CameraPermission.request() }
    ) {
        self.rooms = rooms
        self.checkCamera = checkCamera
        self.requestCamera = requestCamera
    }

    func prepare() async {
        switch checkCamera() {
        case .granted:
            state = .scanning
        case .denied:
            state = .cameraDenied
        case .notDetermined:
            let result = await requestCamera()
            state = result == .granted ? .scanning : .cameraDenied
        }
    }

    func handleScan(_ payload: String) {
        guard case .scanning = state else { return }
        do {
            let invite = try RoomInvite.parse(qrPayload: payload)
            state = .joining
            Task { await join(invite: invite) }
        } catch InviteError.unsupportedVersion(let v) {
            state = .failed("Неподдерживаемая версия приглашения (\(v)).")
        } catch {
            // Не MeshChat QR — продолжаем сканировать
            return
        }
    }

    #if DEBUG
    func handleDebugPaste() {
        handleScan(debugPayloadInput)
    }
    #endif

    private func join(invite: RoomInvite) async {
        do {
            let room = try await rooms.joinRoom(invite: invite)
            joinedRoom = room
        } catch RoomError.nicknameMissing {
            state = .failed("Укажите ник перед входом в комнату")
        } catch {
            logger.error("joinRoom failed: \(error, privacy: .public)")
            state = .failed("Не удалось подключиться к комнате")
        }
    }
}

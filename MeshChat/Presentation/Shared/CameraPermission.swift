// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import AVFoundation

/// Статус разрешения на доступ к камере.
enum CameraPermission {
    case granted
    case denied
    case notDetermined

    /// Проверяет текущий статус разрешения синхронно.
    static func current() -> CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:            return .granted
        case .denied, .restricted:   return .denied
        case .notDetermined:         return .notDetermined
        @unknown default:            return .notDetermined
        }
    }

    /// Запрашивает разрешение и возвращает результат.
    static func request() async -> CameraPermission {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .granted : .denied
    }
}

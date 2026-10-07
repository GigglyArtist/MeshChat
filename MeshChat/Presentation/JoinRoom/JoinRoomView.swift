// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI
import VisionKit

/// Экран входа в комнату по QR-коду (§12.1).
struct JoinRoomView: View {

    @State private var viewModel: JoinRoomViewModel
    private let onSuccess: (ChatRoute) -> Void

    init(rooms: any RoomServicing, onSuccess: @escaping (ChatRoute) -> Void) {
        _viewModel = State(wrappedValue: JoinRoomViewModel(rooms: rooms))
        self.onSuccess = onSuccess
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .checkingCamera:
                ProgressView()
            case .scanning:
                scanningView
            case .cameraDenied:
                cameraDeniedView
            case .joining:
                ProgressView("Подключение…")
            case .failed(let message):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .navigationTitle("Войти по QR")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.prepare() }
        .onChange(of: viewModel.joinedRoute) { _, route in
            if let route { onSuccess(route) }
        }
    }

    @ViewBuilder
    private var scanningView: some View {
        if DataScannerViewController.isSupported {
            QRScannerView { payload in
                viewModel.handleScan(payload)
            }
            .ignoresSafeArea()
        } else {
            #if DEBUG
            debugScannerView
            #else
            ContentUnavailableView(
                "Сканер недоступен",
                systemImage: "camera.viewfinder",
                description: Text("Это устройство не поддерживает сканирование QR-кодов.")
            )
            #endif
        }
    }

    private var cameraDeniedView: some View {
        ContentUnavailableView {
            Label("Нет доступа к камере", systemImage: "camera.fill")
        } description: {
            Text("Разрешите доступ к камере в Настройках, чтобы сканировать QR-коды.")
        } actions: {
            Button("Открыть Настройки") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    #if DEBUG
    private var debugScannerView: some View {
        VStack(spacing: 16) {
            Text("Симулятор: вставьте QR-код вручную")
                .font(.headline)
            TextField("Вставить код", text: $viewModel.debugPayloadInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            Button("Применить") {
                viewModel.handleDebugPaste()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.debugPayloadInput.isEmpty)
        }
        .padding()
    }
    #endif
}

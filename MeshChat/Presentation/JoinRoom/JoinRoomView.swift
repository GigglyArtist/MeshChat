// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI
import VisionKit

/// Экран входа в комнату по QR-коду (§12.1).
struct JoinRoomView: View {

    @State private var viewModel: JoinRoomViewModel

    init(secrets: any RoomSecretProviding) {
        _viewModel = State(wrappedValue: JoinRoomViewModel(secrets: secrets))
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
            case .found(let invite):
                foundView(invite: invite)
            case .failed(let message):
                ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(message))
            }
        }
        .navigationTitle("Войти по QR")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.prepare() }
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

    private func foundView(invite: RoomInvite) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("QR-код распознан")
                .font(.title2.bold())
            Text("Подключение к сервису «\(invite.serviceName)»…")
                .foregroundStyle(.secondary)
        }
        .padding()
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

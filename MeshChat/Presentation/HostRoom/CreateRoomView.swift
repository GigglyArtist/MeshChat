// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Экран создания комнаты: ввод пароля → QR-приглашение (§12.1).
struct CreateRoomView: View {

    @State private var viewModel: CreateRoomViewModel

    init(secrets: any RoomSecretProviding, peerID: UUID) {
        _viewModel = State(wrappedValue: CreateRoomViewModel(secrets: secrets, peerID: peerID))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .editing:
                editingView
            case .ready(let qrPayload):
                RoomQRCodeView(qrPayload: qrPayload)
            case .failed(let message):
                ContentUnavailableView("Ошибка", systemImage: "exclamationmark.triangle", description: Text(message))
            }
        }
        .navigationTitle("Создать комнату")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var editingView: some View {
        Form {
            Section {
                SecureField("Пароль комнаты", text: $viewModel.passwordInput)
                    .textContentType(.newPassword)
            } footer: {
                Text("От 4 до 64 символов.")
            }

            Section {
                Button("Создать") {
                    viewModel.createRoom()
                }
                .disabled(!viewModel.canCreate)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CreateRoomView(secrets: RoomCredentialsFactory(), peerID: UUID())
    }
}
#endif

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Экран создания комнаты: ввод пароля → вызов `RoomServicing.createRoom` → переход в чат (§12.1).
struct CreateRoomView: View {

    @State private var viewModel: CreateRoomViewModel
    private let onSuccess: (any ActiveRoomHandling) -> Void

    init(rooms: any RoomServicing, onSuccess: @escaping (any ActiveRoomHandling) -> Void) {
        _viewModel = State(wrappedValue: CreateRoomViewModel(rooms: rooms))
        self.onSuccess = onSuccess
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .editing:
                editingView
            case .loading:
                ProgressView("Создание комнаты…")
            case .failed(let message):
                ContentUnavailableView(
                    "Ошибка",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .navigationTitle("Создать комнату")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.createdRoom != nil) { _, isSet in
            if isSet, let room = viewModel.createdRoom { onSuccess(room) }
        }
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
                    Task { await viewModel.createRoom() }
                }
                .disabled(!viewModel.canCreate)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CreateRoomView(rooms: PreviewRoomService(), onSuccess: { _ in })
    }
}
#endif

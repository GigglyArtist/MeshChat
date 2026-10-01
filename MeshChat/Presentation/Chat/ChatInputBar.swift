// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Панель ввода сообщения с кнопкой отправки.
struct ChatInputBar: View {

    @Binding var text: String
    let canSend: Bool
    let onSend: () async -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Сообщение…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await onSend() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : Color(.systemGray3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

#if DEBUG
#Preview("Can send") {
    ChatInputBar(text: .constant("Привет"), canSend: true, onSend: {})
}

#Preview("Cannot send") {
    ChatInputBar(text: .constant(""), canSend: false, onSend: {})
}
#endif

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Строка ленты: сообщение или системное уведомление (§12.1.1).
struct ChatRow: View {

    let item: ChatViewModel.Item

    var body: some View {
        switch item {
        case .message(let msg, let isOutgoing, let name):
            MessageBubbleView(
                text: msg.text,
                timestamp: msg.timestamp,
                isOutgoing: isOutgoing,
                authorName: name
            )
        case .notice(_, let text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        }
    }
}

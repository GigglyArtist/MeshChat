// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Пузырёк сообщения: выравнивается вправо для исходящих, влево — для входящих.
struct MessageBubbleView: View {

    let text: String
    let timestamp: Date
    let isOutgoing: Bool
    let authorName: String

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isOutgoing { Spacer(minLength: 48) }
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 2) {
                if !isOutgoing {
                    Text(authorName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                Text(text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isOutgoing ? Color.accentColor : Color(.systemGray5))
                    .foregroundStyle(isOutgoing ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(Self.timeFormatter.string(from: timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            if !isOutgoing { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 8)
    }
}

#if DEBUG
#Preview("Outgoing") {
    MessageBubbleView(
        text: "Привет! Как дела?",
        timestamp: Date(),
        isOutgoing: true,
        authorName: "Вы"
    )
    .padding()
}

#Preview("Incoming") {
    MessageBubbleView(
        text: "Всё отлично, спасибо!",
        timestamp: Date(),
        isOutgoing: false,
        authorName: "Алиса"
    )
    .padding()
}
#endif

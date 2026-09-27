// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.meshchat", category: "ui")

/// Отображает QR-код приглашения в комнату (§6.4).
/// Белая подложка и чёрные модули в обеих темах; максимум 320 pt.
struct RoomQRCodeView: View {

    let qrPayload: String

    var body: some View {
        VStack(spacing: 24) {
            QRCodeImage(payload: qrPayload)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 320)
                .padding()

            #if DEBUG
            Button("Скопировать код") {
                UIPasteboard.general.string = qrPayload
            }
            .font(.footnote)
            #endif
        }
    }
}

#if DEBUG
#Preview {
    RoomQRCodeView(
        qrPayload: #"{"app":"meshchat","key":"2qpp+HKYf19dl/5kt6s+ur0/aGXxSbjbQUE0BNBjl5g=","svc":"6B1F2C8E-3D4A-4F5B-9C7D-8E9F0A1B2C3D","v":1}"#
    )
}
#endif

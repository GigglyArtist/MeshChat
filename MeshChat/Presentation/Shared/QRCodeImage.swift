// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.meshchat", category: "ui")

/// Отображает QR-код для переданной строки без сглаживания (§6.4).
/// Белая подложка — модули всегда чёрные в любой теме.
struct QRCodeImage: View {
    let payload: String

    private let generator = QRCodeGenerator()

    var body: some View {
        if let uiImage = generator.generate(from: payload) {
            Image(uiImage: uiImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .background(Color.white)
        } else {
            let _ = logger.error("QRCodeImage: generate returned nil — cannot display QR code")
            VStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Не удалось построить QR-код")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

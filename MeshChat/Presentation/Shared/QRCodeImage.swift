// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI
import CoreImage

/// Отображает QR-код для переданной строки без сглаживания (§6.4).
struct QRCodeImage: View {
    let payload: String

    private let generator = QRCodeGenerator()

    var body: some View {
        if let ciImage = generator.generate(from: payload) {
            let uiImage = UIImage(ciImage: ciImage)
            Image(uiImage: uiImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            // Резервный вариант — не должен появляться на iOS 17+
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
        }
    }
}

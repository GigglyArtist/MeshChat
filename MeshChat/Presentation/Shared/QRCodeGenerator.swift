// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import CoreImage
import UIKit

/// Генерирует `UIImage` QR-кода из строки (§6.4).
/// Коррекция ошибок M, масштаб ×10. Всегда чёрные модули на белом фоне.
nonisolated struct QRCodeGenerator {

    nonisolated static let scale = 10

    /// Возвращает `UIImage` с рендером через `CIContext` (не через `UIImage(ciImage:)`,
    /// который не даёт CGImage и не рисуется в SwiftUI / ImageRenderer).
    nonisolated func generate(from string: String) -> UIImage? {
        guard
            let filter = CIFilter(name: "CIQRCodeGenerator"),
            let data = string.data(using: .utf8)
        else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciOutput = filter.outputImage else { return nil }

        let scaled = ciOutput.transformed(by: CGAffineTransform(
            scaleX: CGFloat(QRCodeGenerator.scale),
            y: CGFloat(QRCodeGenerator.scale)
        ))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage).withRenderingMode(.alwaysOriginal)
    }
}

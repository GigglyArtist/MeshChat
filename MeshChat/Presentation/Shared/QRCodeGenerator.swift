// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import CoreImage
import Foundation

/// Генерирует `CIImage` QR-кода из строки (§6.4).
/// Коррекция ошибок M, масштаб ×10.
struct QRCodeGenerator {

    static let scale = 10

    /// - Returns: `CIImage` или `nil`, если фильтр недоступен (никогда на iOS 17+).
    func generate(from string: String) -> CIImage? {
        guard
            let filter = CIFilter(name: "CIQRCodeGenerator"),
            let data = string.data(using: .utf8)
        else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: CGFloat(QRCodeGenerator.scale),
                                          y: CGFloat(QRCodeGenerator.scale))
        return output.transformed(by: transform)
    }
}

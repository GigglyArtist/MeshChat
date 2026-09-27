// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import CoreImage
import UIKit
import Foundation
@testable import MeshChat

@Suite("QRCodeGenerator")
struct QRCodeGeneratorTests {

    private let generator = QRCodeGenerator()

    @Test("Генерирует UIImage для непустой строки")
    func generateNonEmpty() {
        let image = generator.generate(from: "hello")
        #expect(image != nil)
    }

    @Test("Результирующий размер соответствует масштабу ×10")
    func scaleApplied() {
        guard let image = generator.generate(from: "A") else {
            Issue.record("generate(from:) вернул nil")
            return
        }
        // QR версии 1 — 21×21 модулей; с тихой зоной ≥ 25×25 модулей ×10 ≥ 250 пикселей
        #expect(image.size.width >= 210)
        #expect(image.size.height >= 210)
    }

    @Test("Roundtrip: строка кодируется в QR и детектируется обратно через CIDetector")
    func roundtripWithCIDetector() {
        let original = "meshchat-test-string"
        guard let uiImage = generator.generate(from: original),
              let cgImage = uiImage.cgImage else {
            Issue.record("generate вернул nil или не имеет cgImage")
            return
        }
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: [
            CIDetectorAccuracy: CIDetectorAccuracyHigh
        ])
        let features = detector?.features(in: ciImage) ?? []
        guard let qrFeature = features.first as? CIQRCodeFeature else {
            Issue.record("CIDetector не нашёл QR-код")
            return
        }
        #expect(qrFeature.messageString == original)
    }
}

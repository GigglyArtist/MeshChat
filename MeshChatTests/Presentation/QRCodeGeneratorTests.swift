// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import CoreImage
import Foundation
@testable import MeshChat

@Suite("QRCodeGenerator")
struct QRCodeGeneratorTests {

    private let generator = QRCodeGenerator()

    @Test("Генерирует CIImage для непустой строки")
    func generateNonEmpty() {
        let image = generator.generate(from: "hello")
        #expect(image != nil)
    }

    @Test("Результирующий размер соответствует масштабу ×10")
    func scaleApplied() {
        let image = generator.generate(from: "A")
        // QR версии 1 — 21×21 модулей; с тихой зоной ≥ 25×25 модулей ×10 ≥ 250 пикселей
        if let img = image {
            #expect(img.extent.width >= 210)
            #expect(img.extent.height >= 210)
        } else {
            Issue.record("generate(from:) вернул nil")
        }
    }

    @Test("Roundtrip: строка кодируется в QR и детектируется обратно через CIDetector")
    func roundtripWithCIDetector() throws {
        let original = "meshchat-test-string"
        guard let ciImage = generator.generate(from: original) else {
            Issue.record("generate вернул nil")
            return
        }
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

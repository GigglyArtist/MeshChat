// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
@testable import MeshChat

private let golden = #"{"app":"meshchat","key":"2qpp+HKYf19dl/5kt6s+ur0/aGXxSbjbQUE0BNBjl5g=","svc":"6B1F2C8E-3D4A-4F5B-9C7D-8E9F0A1B2C3D","v":1}"#

@Suite("RoomQRCodeView rendering", .serialized)
@MainActor
struct RoomQRCodeViewRenderingTests {

    @Test("QR payload detectable via ImageRenderer", arguments: [ColorScheme.light, ColorScheme.dark])
    func qrPayloadDetectable(scheme: ColorScheme) {
        let view = RoomQRCodeView(qrPayload: golden)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 390, height: 844)
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            Issue.record("ImageRenderer returned nil cgImage (\(scheme))")
            return
        }

        let ciImage = CIImage(cgImage: cgImage)
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: CIContext(),
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: ciImage) ?? []
        guard let qrFeature = features.first as? CIQRCodeFeature else {
            Issue.record("CIDetector found no QR code in rendered view (\(scheme))")
            return
        }
        #expect(qrFeature.messageString == golden)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI
import VisionKit
import Vision
import os

// os — не в списке Presentation, но Logger обязателен по CLAUDE.md для QRScannerView.

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.meshchat", category: "ui")

/// Обёртка над `DataScannerViewController` для сканирования QR-кодов (§6.4).
/// `DataScannerViewController.isSupported == false` в симуляторе — отладочный обходной путь
/// реализован в `JoinRoomView` (`#if DEBUG`).
struct QRScannerView: UIViewControllerRepresentable {

    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        guard !vc.isScanning else { return }
        do {
            try vc.startScanning()
        } catch {
            logger.error("QR scanner failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                if case let .barcode(barcode) = item,
                   let payload = barcode.payloadStringValue {
                    onScan(payload)
                    return
                }
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            logger.error("QR scanner became unavailable: \(error, privacy: .public)")
        }
    }
}

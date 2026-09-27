// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Отображает QR-код приглашения в комнату (§6.4).
struct RoomQRCodeView: View {

    let invite: RoomInvite

    private var qrPayload: String? {
        try? invite.qrPayload()
    }

    var body: some View {
        VStack(spacing: 24) {
            if let payload = qrPayload {
                QRCodeImage(payload: payload)
                    .frame(maxWidth: 280, maxHeight: 280)
                    .padding()

                #if DEBUG
                Button("Скопировать код") {
                    UIPasteboard.general.string = payload
                }
                .font(.footnote)
                #endif
            } else {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
                Text("Не удалось сформировать QR-код")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

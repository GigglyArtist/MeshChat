// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Главный экран: создать комнату, войти по QR, история (§12.1).
struct HomeView: View {

    let nickname: String
    let onCreateRoom: () -> Void
    let onJoinRoom: () -> Void
    let onHistory: () -> Void

    var body: some View {
        List {
            Section {
                Button(action: onCreateRoom) {
                    Label("Создать комнату", systemImage: "plus.circle.fill")
                }
                Button(action: onJoinRoom) {
                    Label("Войти по QR", systemImage: "qrcode.viewfinder")
                }
            }

            Section {
                Button(action: onHistory) {
                    Label("История", systemImage: "clock")
                }
            }
        }
        .navigationTitle(nickname)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        HomeView(nickname: "Preview", onCreateRoom: {}, onJoinRoom: {}, onHistory: {})
    }
}
#endif

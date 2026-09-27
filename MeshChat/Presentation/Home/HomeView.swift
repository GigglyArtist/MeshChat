// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Главный экран: создать комнату, войти по QR, история (§12.1).
/// Полная реализация добавляется в этапах 3–10 дорожной карты.
struct HomeView: View {

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "MeshChat",
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text("Создайте комнату или войдите по QR-коду.")
            )
            .navigationTitle("MeshChat")
        }
    }
}

#Preview {
    HomeView()
}

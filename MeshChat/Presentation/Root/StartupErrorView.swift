// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Показывается, когда хранилище или Keychain не удалось инициализировать (§12.1).
struct StartupErrorView: View {

    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Не удалось запустить приложение")
                .font(.headline)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

#Preview {
    StartupErrorView(message: "Не удалось загрузить хранилище данных. Попробуйте переустановить приложение.")
}

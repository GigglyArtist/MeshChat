// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

@main
struct MeshChatApp: App {
    @State private var startup = AppStartup.live()

    var body: some Scene {
        WindowGroup {
            switch startup {
            case .ready(let environment):
                RootView(environment: environment)
            case .failed(let message):
                StartupErrorView(message: message)
            }
        }
    }
}

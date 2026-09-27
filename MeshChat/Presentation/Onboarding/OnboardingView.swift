// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import SwiftUI

/// Экран первого запуска: ввод никнейма (§12.1).
struct OnboardingView: View {

    @State private var viewModel: OnboardingViewModel

    init(identity: any IdentityProviding, onComplete: @escaping () -> Void) {
        _viewModel = State(wrappedValue: OnboardingViewModel(identity: identity, onComplete: onComplete))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Добро пожаловать в MeshChat")
                .font(.title2)
                .bold()
            Text("Введите имя, которое увидят ваши собеседники.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("Ваше имя", text: $viewModel.nicknameInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .padding(.horizontal)
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Button("Продолжить") { viewModel.continueAction() }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canContinue)
            Spacer()
        }
        .padding()
    }
}

#if DEBUG
#Preview {
    OnboardingView(identity: PreviewIdentityProvider(nickname: nil), onComplete: {})
}
#endif

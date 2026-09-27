// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Observation

/// Управляет экраном ввода никнейма при первом запуске (§12.1).
@Observable @MainActor final class OnboardingViewModel {

    var nicknameInput: String = ""
    private(set) var errorMessage: String?

    /// `true`, если введённый ник пройдёт валидацию `NicknamePolicy`.
    var canContinue: Bool { NicknamePolicy.normalize(nicknameInput) != nil }

    private let identity: any IdentityProviding
    private let onComplete: () -> Void

    init(identity: any IdentityProviding, onComplete: @escaping () -> Void) {
        self.identity = identity
        self.onComplete = onComplete
    }

    /// Нормализует ник, сохраняет через `identity` и вызывает `onComplete`.
    func continueAction() {
        guard NicknamePolicy.normalize(nicknameInput) != nil else { return }
        do {
            try identity.setNickname(nicknameInput)
            onComplete()
        } catch {
            errorMessage = "Не удалось сохранить имя. Попробуйте ещё раз."
        }
    }
}

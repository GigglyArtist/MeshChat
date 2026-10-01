// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import UIKit
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.meshchat", category: "ui")

/// ViewModel экрана чата (§12.1.1, §12.2).
///
/// События комнаты читаются в собственной задаче (`start()`), а не в `.task` View:
/// отмена `.task` при исчезновении View навсегда завершает `AsyncStream` (§12.2).
@Observable @MainActor final class ChatViewModel {

    // MARK: - Тип элемента ленты (§12.1.1)

    enum Item: Identifiable {
        case message(ChatMessage, isOutgoing: Bool, authorName: String)
        case notice(id: UUID, text: String)

        var id: UUID {
            switch self {
            case .message(let m, _, _): return m.id
            case .notice(let id, _): return id
            }
        }
    }

    // MARK: - Состояние (читается View)

    private(set) var items: [Item] = []
    private(set) var participants: [PeerProfile] = []
    private(set) var sessionState: SessionState = .connecting
    private(set) var sendError: String?
    var draft: String = ""

    /// Видимость поля ввода: скрыто в терминальных ended-состояниях (§12.3).
    var isInputVisible: Bool {
        switch sessionState {
        case .connecting, .active, .reconnecting: return true
        case .ended: return false
        }
    }

    /// Кнопка «Отправить» активна только в `.active` с непустым черновиком.
    var canSend: Bool {
        guard case .active = sessionState else { return false }
        return MessageTextPolicy.normalize(draft) != nil
    }

    /// Роль — хост или клиент (влияет на надпись кнопки выхода).
    var role: SessionRole { room.role }
    /// QR-приглашение: только у хоста.
    var invite: RoomInvite? { room.invite }

    // MARK: - Приватное состояние

    private let room: any ActiveRoomHandling
    // peerNames пополняется из participantsChanged; ушедшие не удаляются (§12.1.1).
    private var peerNames: [UUID: String] = [:]
    private var eventTask: Task<Void, Never>?

    // MARK: - Init / deinit

    init(room: any ActiveRoomHandling, localNickname: String) {
        self.room = room
        peerNames[room.localPeerID] = localNickname
        UIApplication.shared.isIdleTimerDisabled = true
    }

    // MARK: - Публичный API

    /// Запускает чтение событий комнаты. Идемпотентен — безопасно вызывать из `.onAppear`.
    func start() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in room.events {
                handle(event)
            }
        }
    }

    func send() async {
        guard let text = MessageTextPolicy.normalize(draft) else { return }
        sendError = nil
        do {
            try await room.send(text: text)
            draft = ""
        } catch {
            sendError = error.localizedDescription
            logger.error("send failed: \(error, privacy: .public)")
        }
    }

    func leave() async {
        await room.leave()
    }

    /// Останавливает чтение событий. Вызывается из `.onDisappear` View.
    func stop() {
        eventTask?.cancel()
        eventTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func resetSendError() {
        sendError = nil
    }

    // MARK: - Обработка событий

    private func handle(_ event: RoomEvent) {
        switch event {
        case .stateChanged(let state):
            sessionState = state

        case .participantsChanged(let profiles):
            participants = profiles
            for p in profiles { peerNames[p.id] = p.nickname }

        case .messageAppended(let message):
            let isOutgoing = message.senderID == room.localPeerID
            let name = isOutgoing ? "Вы" : (peerNames[message.senderID] ?? "Неизвестный")
            items.append(.message(message, isOutgoing: isOutgoing, authorName: name))

        case .notice(let notice):
            items.append(.notice(id: UUID(), text: noticeText(notice)))
        }
    }

    private func noticeText(_ notice: RoomNotice) -> String {
        switch notice {
        case .joined(let name): return "\(name) присоединился"
        case .left(let name, let reason):
            switch reason {
            case .left: return "\(name) вышел"
            case .connectionLost: return "\(name) отключился"
            }
        }
    }
}

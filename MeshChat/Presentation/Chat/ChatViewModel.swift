// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
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

    /// Счётчик участников вместе с собой: «1 участник», «3 участника», «5 участников» (§12.1.1).
    var participantCountTitle: String {
        let count = participants.count + 1
        let word = RussianPlural.word(for: count, one: "участник", few: "участника", many: "участников")
        return "\(count) \(word)"
    }

    /// Роль — хост или клиент (влияет на надпись кнопки выхода).
    var role: SessionRole { room.role }
    /// QR-приглашение: только у хоста.
    var invite: RoomInvite? { room.invite }

    /// QR-payload для sheet-а хоста. `nil` — не хост или ошибка кодирования (логируется).
    var qrPayload: String? {
        guard let invite = room.invite else { return nil }
        do {
            return try invite.qrPayload()
        } catch {
            logger.error("qrPayload build failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// Повторный вход: кнопка «Подключиться снова» (§12.1.1).
    private(set) var canRejoin: Bool = false
    private(set) var isRejoining: Bool = false
    private(set) var rejoinedRoute: ChatRoute?
    /// Установлен при уходе с экрана чата. Позволяет `rejoin()` покинуть осиротевшую комнату.
    private(set) var exitedToHome: Bool = false

    // MARK: - Приватное состояние

    private let room: any ActiveRoomHandling
    private let rejoinInvite: RoomInvite?
    private let rooms: (any RoomServicing)?
    // peerNames пополняется из participantsChanged; ушедшие не удаляются (§12.1.1).
    private var peerNames: [UUID: String] = [:]
    private var eventTask: Task<Void, Never>?

    // MARK: - Init / deinit

    init(room: any ActiveRoomHandling,
         localNickname: String,
         rejoinInvite: RoomInvite? = nil,
         rooms: (any RoomServicing)? = nil) {
        self.room = room
        self.rejoinInvite = rejoinInvite
        self.rooms = rooms
        peerNames[room.localPeerID] = localNickname
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

    /// Вызывается перед уходом с экрана чата; блокирует навигацию из `rejoin()`.
    func exitToHome() {
        exitedToHome = true
    }

    /// Останавливает чтение событий. Вызывается из `.onDisappear` View.
    func stop() {
        eventTask?.cancel()
        eventTask = nil
    }

    /// Вызывается, когда приложение возвращается на передний план (ADR-11).
    func appDidBecomeActive() async {
        await room.appDidBecomeActive()
    }

    func resetSendError() {
        sendError = nil
    }

    // MARK: - Обработка событий

    /// Подключиться снова с тем же приглашением после обрыва (§12.1.1).
    ///
    /// Если пользователь ушёл с экрана до завершения подключения (`exitedToHome == true`),
    /// покидает созданную комнату: у неё нет владельца (ADR-13).
    func rejoin() async {
        guard let invite = rejoinInvite, let rooms = rooms else { return }
        isRejoining = true
        sendError = nil
        do {
            let newRoom = try await rooms.joinRoom(invite: invite)
            if exitedToHome {
                await newRoom.leave()
                return
            }
            isRejoining = false
            rejoinedRoute = ChatRoute(room: newRoom, rejoinInvite: invite)
        } catch {
            logger.error("rejoin failed: \(error, privacy: .public)")
            sendError = "Не удалось подключиться к комнате"
            isRejoining = false
        }
    }

    private func updateCanRejoin() {
        guard rejoinInvite != nil, rooms != nil, !isRejoining else { canRejoin = false; return }
        if case .ended(let reason) = sessionState {
            switch reason {
            case .hostLost, .hostUnreachable, .handshakeTimeout: canRejoin = true
            default: canRejoin = false
            }
        } else {
            canRejoin = false
        }
    }

    private func handle(_ event: RoomEvent) {
        switch event {
        case .stateChanged(let state):
            sessionState = state
            updateCanRejoin()

        case .participantsChanged(let profiles):
            participants = profiles
            for p in profiles { peerNames[p.id] = p.nickname }

        case .messageAppended(let message):
            let isOutgoing = message.senderID == room.localPeerID
            let name = isOutgoing ? "Вы" : (peerNames[message.senderID] ?? "Неизвестный")
            items.append(.message(message, isOutgoing: isOutgoing, authorName: name))

        case .notice(let notice):
            items.append(.notice(id: UUID(), text: noticeText(notice)))

        case .messagesRestored(let messages, let knownPeers):
            for p in knownPeers { peerNames[p.id] = p.nickname }
            items.append(.notice(id: UUID(), text: "Ранее в этой комнате"))
            for message in messages {
                let isOutgoing = message.senderID == room.localPeerID
                let name = isOutgoing ? "Вы" : (peerNames[message.senderID] ?? "Неизвестный")
                items.append(.message(message, isOutgoing: isOutgoing, authorName: name))
            }
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

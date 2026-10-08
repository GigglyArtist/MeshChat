// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Testing
import Foundation
@testable import MeshChat

/// `@MainActor` нужен: `ChatViewModel.init` и `FakeActiveRoom.init` выводятся как
/// `@MainActor`-изолированные при `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
@MainActor
@Suite("ChatViewModel", .serialized)
struct ChatViewModelTests {

    // MARK: - Вспомогательные методы

    func makeViewModel(
        role: SessionRole = .host,
        nickname: String = "Alice"
    ) -> (ChatViewModel, FakeActiveRoom) {
        let room = FakeActiveRoom(role: role)
        let vm = ChatViewModel(room: room, localNickname: nickname)
        return (vm, room)
    }

    /// Ожидает наступления условия с поллингом (§16.3).
    ///
    /// Каждые 20 мс отпускает MainActor, давая eventTask ViewModel обработать события.
    func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        if condition() { return }
        struct WaitTimeout: Error, CustomStringConvertible {
            var description: String { "waitUntil timed out" }
        }
        throw WaitTimeout()
    }

    // MARK: 1. start() идемпотентен

    @Test("start() дважды не создаёт дублирующий цикл событий")
    func startIsIdempotent() async throws {
        let (vm, room) = makeViewModel()
        vm.start()
        vm.start()  // второй вызов — no-op

        let alice = PeerProfile(id: UUID(), nickname: "Alice")
        room.emit(.participantsChanged([alice]))
        try await waitUntil { vm.participants.count == 1 }

        #expect(vm.participants.count == 1)
    }

    // MARK: 2. participantsChanged → обновляет participants и peerNames

    @Test("participantsChanged обновляет participants")
    func participantsChangedUpdatesParticipants() async throws {
        let (vm, room) = makeViewModel()
        vm.start()

        let alice = PeerProfile(id: UUID(), nickname: "Alice")
        let bob = PeerProfile(id: UUID(), nickname: "Bob")
        room.emit(.participantsChanged([alice, bob]))
        try await waitUntil { vm.participants.count == 2 }

        #expect(vm.participants.count == 2)
    }

    // MARK: 3. messageAppended → добавляет элемент в ленту

    @Test("messageAppended добавляет входящее сообщение в ленту")
    func messageAppendedAddsToFeed() async throws {
        let (vm, room) = makeViewModel()
        vm.start()

        let senderID = UUID()
        let peer = PeerProfile(id: senderID, nickname: "Bob")
        room.emit(.participantsChanged([peer]))
        let msg = ChatMessage(id: UUID(), text: "hello",
                              timestamp: Date().flooredToMilliseconds, senderID: senderID)
        room.emit(.messageAppended(msg))
        try await waitUntil { vm.items.count == 1 }

        #expect(vm.items.count == 1)
        if case .message(let m, let isOut, let name) = vm.items[0] {
            #expect(m.id == msg.id)
            #expect(!isOut)
            #expect(name == "Bob")
        } else {
            Issue.record("Expected .message, got \(vm.items[0])")
        }
    }

    @Test("messageAppended с localPeerID помечает как исходящее")
    func messageAppendedOutgoing() async throws {
        let localID = UUID()
        let room = FakeActiveRoom(role: .host, localPeerID: localID)
        let vm = ChatViewModel(room: room, localNickname: "Вы")
        vm.start()

        let msg = ChatMessage(id: UUID(), text: "hi",
                              timestamp: Date().flooredToMilliseconds, senderID: localID)
        room.emit(.messageAppended(msg))
        try await waitUntil { !vm.items.isEmpty }

        if case .message(_, let isOut, let name) = vm.items.first {
            #expect(isOut)
            #expect(name == "Вы")
        } else {
            Issue.record("Expected outgoing message, got \(vm.items)")
        }
    }

    // MARK: 4. notice → добавляет системную строку

    @Test("notice(.joined) добавляет системную строку в ленту")
    func noticeJoinedAddsToFeed() async throws {
        let (vm, room) = makeViewModel()
        vm.start()

        room.emit(.notice(.joined(nickname: "Charlie")))
        try await waitUntil { !vm.items.isEmpty }

        if case .notice(_, let text) = vm.items.first {
            #expect(text == "Charlie присоединился")
        } else {
            Issue.record("Expected .notice, got \(vm.items)")
        }
    }

    // MARK: 5. stateChanged → обновляет sessionState

    @Test("stateChanged обновляет sessionState")
    func stateChangedUpdatesState() async throws {
        let (vm, room) = makeViewModel()
        vm.start()

        room.emit(.stateChanged(.active))
        try await waitUntil { if case .active = vm.sessionState { return true }; return false }

        if case .active = vm.sessionState { } else {
            Issue.record("Expected .active, got \(vm.sessionState)")
        }
    }

    // MARK: 6. canSend — зависит от состояния и черновика

    @Test("canSend == false при состоянии .connecting")
    func canSendFalseWhenConnecting() {
        let (vm, _) = makeViewModel()
        vm.draft = "hello"
        #expect(!vm.canSend)
    }

    @Test("canSend == true при .active и непустом черновике")
    func canSendTrueWhenActive() async throws {
        let (vm, room) = makeViewModel()
        vm.start()
        room.emit(.stateChanged(.active))
        try await waitUntil { if case .active = vm.sessionState { return true }; return false }

        vm.draft = "hello"
        #expect(vm.canSend)
    }

    @Test("canSend == false при .active и пустом черновике")
    func canSendFalseWhenDraftEmpty() async throws {
        let (vm, room) = makeViewModel()
        vm.start()
        room.emit(.stateChanged(.active))
        try await waitUntil { if case .active = vm.sessionState { return true }; return false }

        vm.draft = "   "
        #expect(!vm.canSend)
    }

    // MARK: 7. send() — вызывает room.send и очищает черновик

    @Test("send() вызывает room.send и очищает draft")
    func sendCallsRoomSend() async throws {
        let (vm, room) = makeViewModel()
        vm.start()
        room.emit(.stateChanged(.active))
        try await waitUntil { if case .active = vm.sessionState { return true }; return false }

        vm.draft = "hello"
        await vm.send()

        #expect(room.sentTexts == ["hello"])
        #expect(vm.draft.isEmpty)
        #expect(vm.sendError == nil)
    }

    @Test("send() с ошибкой сохраняет draft и устанавливает sendError")
    func sendErrorPreservesDraft() async throws {
        let (vm, room) = makeViewModel()
        room.sendError = NetworkError.notActive
        vm.start()
        room.emit(.stateChanged(.active))
        try await waitUntil { if case .active = vm.sessionState { return true }; return false }

        vm.draft = "hello"
        await vm.send()

        #expect(!vm.draft.isEmpty)
        #expect(vm.sendError != nil)
    }

    // MARK: 8. leave() — вызывает room.leave

    @Test("leave() вызывает room.leave")
    func leaveCallsRoomLeave() async {
        let (vm, room) = makeViewModel()
        await vm.leave()
        #expect(room.leaveCount == 1)
    }

    // MARK: 9. appDidBecomeActive() — форвардирует в room

    @Test("appDidBecomeActive() forwards to room.appDidBecomeActive()")
    func appDidBecomeActiveForwards() async {
        let (vm, room) = makeViewModel()
        await vm.appDidBecomeActive()
        #expect(room.appDidBecomeActiveCount == 1)
    }

    // MARK: 10. messagesRestored → уведомление и сообщения в ленте

    @Test("messagesRestored inserts divider notice then messages with correct author names")
    func messagesRestoredAddsFeed() async throws {
        let localID = UUID()
        let peerID = UUID()
        let room = FakeActiveRoom(role: .client, localPeerID: localID)
        let peer = PeerProfile(id: peerID, nickname: "Alice")
        let vm = ChatViewModel(room: room, localNickname: "Я")
        vm.start()

        let t1 = Date(timeIntervalSince1970: 100).flooredToMilliseconds
        let t2 = Date(timeIntervalSince1970: 200).flooredToMilliseconds
        let m1 = ChatMessage(id: UUID(), text: "от Alice", timestamp: t1, senderID: peerID)
        let m2 = ChatMessage(id: UUID(), text: "от меня",  timestamp: t2, senderID: localID)
        room.emit(.messagesRestored([m1, m2], knownPeers: [peer]))

        try await waitUntil { vm.items.count == 3 }

        if case .notice(_, let text) = vm.items[0] {
            #expect(text == "Ранее в этой комнате")
        } else {
            Issue.record("Expected notice as items[0], got \(vm.items[0])")
        }
        if case .message(let m, let isOut, let name) = vm.items[1] {
            #expect(m.id == m1.id)
            #expect(!isOut)
            #expect(name == "Alice")
        } else {
            Issue.record("Expected .message for m1")
        }
        if case .message(let m, let isOut, let name) = vm.items[2] {
            #expect(m.id == m2.id)
            #expect(isOut)
            #expect(name == "Вы")
        } else {
            Issue.record("Expected .message for m2")
        }
    }

    // MARK: 11. canRejoin зависит от причины завершения

    @Test("canRejoin is true for reconnectable end reasons",
          arguments: [SessionEndReason.hostLost, .hostUnreachable, .handshakeTimeout])
    func canRejoinTrueForReason(reason: SessionEndReason) async throws {
        let invite = RoomInvite(version: 1, serviceName: UUID().uuidString,
                                roomKey: Data(repeating: 0xAB, count: 32))
        let room = FakeActiveRoom(role: .client)
        let vm = ChatViewModel(room: room, localNickname: "Я",
                               rejoinInvite: invite, rooms: FakeRoomService())
        vm.start()
        room.emit(.stateChanged(.ended(reason)))
        try await waitUntil { if case .ended = vm.sessionState { return true }; return false }
        #expect(vm.canRejoin)
    }

    @Test("canRejoin is false for intentional end reasons",
          arguments: [SessionEndReason.hostEnded, .leftByUser, .rejected])
    func canRejoinFalseForReason(reason: SessionEndReason) async throws {
        let invite = RoomInvite(version: 1, serviceName: UUID().uuidString,
                                roomKey: Data(repeating: 0xAB, count: 32))
        let room = FakeActiveRoom(role: .client)
        let vm = ChatViewModel(room: room, localNickname: "Я",
                               rejoinInvite: invite, rooms: FakeRoomService())
        vm.start()
        room.emit(.stateChanged(.ended(reason)))
        try await waitUntil { if case .ended = vm.sessionState { return true }; return false }
        #expect(!vm.canRejoin)
    }

    @Test("canRejoin is false without rejoinInvite (host)")
    func canRejoinFalseWithoutInvite() async throws {
        let (vm, room) = makeViewModel(role: .host)
        vm.start()
        room.emit(.stateChanged(.ended(.hostLost)))
        try await waitUntil { if case .ended = vm.sessionState { return true }; return false }
        #expect(!vm.canRejoin)
    }

    // MARK: 12. Успешный rejoin()

    @Test("successful rejoin() calls rooms.joinRoom once and sets rejoinedRoute")
    func rejoinSuccessSetsRoute() async throws {
        let invite = RoomInvite(version: 1, serviceName: UUID().uuidString,
                                roomKey: Data(repeating: 0xAB, count: 32))
        let service = FakeRoomService()
        let room = FakeActiveRoom(role: .client)
        let vm = ChatViewModel(room: room, localNickname: "Я",
                               rejoinInvite: invite, rooms: service)
        vm.start()
        room.emit(.stateChanged(.ended(.hostLost)))
        try await waitUntil { vm.canRejoin }

        await vm.rejoin()

        #expect(service.joinCallCount == 1)
        #expect(service.lastJoinedInvite == invite)
        #expect(vm.rejoinedRoute != nil)
        #expect(vm.rejoinedRoute?.rejoinInvite == invite)
    }

    // MARK: 13. Ошибка rejoin()

    @Test("rejoin() error sets sendError and restores canRejoin")
    func rejoinErrorSetsMessage() async throws {
        let invite = RoomInvite(version: 1, serviceName: UUID().uuidString,
                                roomKey: Data(repeating: 0xAB, count: 32))
        let service = FakeRoomService(joinError: .nicknameMissing)
        let room = FakeActiveRoom(role: .client)
        let vm = ChatViewModel(room: room, localNickname: "Я",
                               rejoinInvite: invite, rooms: service)
        vm.start()
        room.emit(.stateChanged(.ended(.hostLost)))
        try await waitUntil { vm.canRejoin }

        await vm.rejoin()

        #expect(vm.sendError == "Не удалось подключиться к комнате")
        #expect(vm.rejoinedRoute == nil)
        #expect(vm.canRejoin)
    }

    // MARK: 14. Успешный rejoin() сбрасывает спиннер

    @Test("successful rejoin() resets isRejoining to false")
    func rejoinSuccessClearsSpinner() async throws {
        let invite = RoomInvite(version: 1, serviceName: UUID().uuidString,
                                roomKey: Data(repeating: 0xAB, count: 32))
        let service = FakeRoomService()
        let room = FakeActiveRoom(role: .client)
        let vm = ChatViewModel(room: room, localNickname: "Я",
                               rejoinInvite: invite, rooms: service)
        vm.start()
        room.emit(.stateChanged(.ended(.hostLost)))
        try await waitUntil { vm.canRejoin }

        await vm.rejoin()

        #expect(!vm.isRejoining, "spinner must clear on success")
    }

    // MARK: 15. Уход с экрана во время rejoin → осиротевшая комната покидается

    @Test("exitToHome() before rejoin completes causes rejoin() to leave the new room")
    func exitDuringRejoinLeavesOrphanedRoom() async throws {
        let invite = RoomInvite(version: 1, serviceName: UUID().uuidString,
                                roomKey: Data(repeating: 0xAB, count: 32))
        let service = FakeRoomService()
        service.enableJoinGate()
        let room = FakeActiveRoom(role: .client)
        let vm = ChatViewModel(room: room, localNickname: "Я",
                               rejoinInvite: invite, rooms: service)
        vm.start()
        room.emit(.stateChanged(.ended(.hostLost)))
        try await waitUntil { vm.canRejoin }

        // Запускаем rejoin в фоне — он зависнет на gate внутри joinRoom
        let rejoinTask = Task { await vm.rejoin() }

        // Ждём, пока joinRoom заблокируется, затем имитируем уход с экрана
        await service.waitForJoinBlocked()
        vm.exitToHome()

        // Разблокируем joinRoom — он вернёт joinedRoom
        service.releaseJoin()
        await rejoinTask.value

        // Осиротевшая комната должна быть покинута; навигация не должна происходить
        #expect(service.joinedRoom.leaveCount == 1, "orphaned room must be left")
        #expect(vm.rejoinedRoute == nil, "screen is gone — no navigation")
    }

    // MARK: 16. participantCountTitle склоняется правильно

    @Test("participantCountTitle counts self plus remote participants",
          arguments: zip([0, 1, 4], ["1 участник", "2 участника", "5 участников"]))
    func participantCountTitle(peerCount: Int, expected: String) async throws {
        let (vm, room) = makeViewModel()
        vm.start()
        let profiles = (0..<peerCount).map { _ in PeerProfile(id: UUID(), nickname: "Peer") }
        room.emit(.participantsChanged(profiles))
        try await waitUntil { vm.participants.count == peerCount }
        #expect(vm.participantCountTitle == expected)
    }
}

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

    // MARK: 1. start() идемпотентен

    @Test("start() дважды не создаёт дублирующий цикл событий")
    func startIsIdempotent() async throws {
        let (vm, room) = makeViewModel()
        vm.start()
        vm.start()  // второй вызов — no-op

        let alice = PeerProfile(id: UUID(), nickname: "Alice")
        room.emit(.participantsChanged([alice]))
        try await Task.sleep(for: .milliseconds(100))

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
        try await Task.sleep(for: .milliseconds(100))

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
        try await Task.sleep(for: .milliseconds(100))

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
        try await Task.sleep(for: .milliseconds(100))

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
        try await Task.sleep(for: .milliseconds(100))

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
        try await Task.sleep(for: .milliseconds(100))

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
        try await Task.sleep(for: .milliseconds(100))

        vm.draft = "hello"
        #expect(vm.canSend)
    }

    @Test("canSend == false при .active и пустом черновике")
    func canSendFalseWhenDraftEmpty() async throws {
        let (vm, room) = makeViewModel()
        vm.start()
        room.emit(.stateChanged(.active))
        try await Task.sleep(for: .milliseconds(100))

        vm.draft = "   "
        #expect(!vm.canSend)
    }

    // MARK: 7. send() — вызывает room.send и очищает черновик

    @Test("send() вызывает room.send и очищает draft")
    func sendCallsRoomSend() async throws {
        let (vm, room) = makeViewModel()
        vm.start()
        room.emit(.stateChanged(.active))
        try await Task.sleep(for: .milliseconds(100))

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
        try await Task.sleep(for: .milliseconds(100))

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
}

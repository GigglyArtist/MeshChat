// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

/// Интеграционные тесты сессий поверх реального TLS-PSK через loopback (§7.5, §7.6).
///
/// `HostSession` использует `ListenerTap` (обёртку над `BonjourHostListener`),
/// `ClientSession` — `LoopbackClientConnector` на порт, сообщённый `ListenerTap`.
/// Все сетевые операции реальные; таймауты из `NetworkConfiguration.loopback`.
@MainActor
@Suite("SessionLoopback", .serialized, .timeLimit(.minutes(2)))
struct SessionLoopbackTests {

    // MARK: - Вспомогательные фабрики

    func makeSecret(byte: UInt8 = 0xAB) throws -> any RoomSecret {
        try RoomCredentials(roomKeyData: Data(repeating: byte, count: 32))
    }

    func makeHostSession(
        identity: LocalIdentity = .makeTest(nickname: "Host"),
        secret: any RoomSecret,
        tap: ListenerTap
    ) -> HostSession {
        HostSession(
            identity: identity,
            secret: secret,
            listener: tap,
            configuration: .loopback
        )
    }

    func makeClientSession(
        identity: LocalIdentity = .makeTest(nickname: "Client"),
        invite: RoomInvite,
        secret: any RoomSecret,
        port: UInt16
    ) -> ClientSession {
        ClientSession(
            identity: identity,
            invite: invite,
            secret: secret,
            connector: LoopbackClientConnector(port: port),
            configuration: .loopback
        )
    }

    // MARK: - Тест 1: полный happy-path

    /// Хост стартует → клиент присоединяется → обмен сообщениями → хост завершает.
    @Test("happyPath: host starts, client joins, exchange messages, host ends")
    func happyPath() async throws {
        let secret = try makeSecret()
        let hostID = LocalIdentity.makeTest(nickname: "Host")
        let clientID = LocalIdentity.makeTest(nickname: "Client")

        let tap = ListenerTap()
        let host = makeHostSession(identity: hostID, secret: secret, tap: tap)
        let hostProbe = EventProbe<SessionEvent>(stream: host.events)

        // Запускаем хост и ждём `.active`.
        Task { await host.start() }
        _ = try await hostProbe.waitFor(timeout: .seconds(10)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        let port = try await tap.waitForPort()
        let client = makeClientSession(
            identity: clientID,
            invite: host.invite,
            secret: secret,
            port: port
        )
        let clientProbe = EventProbe<SessionEvent>(stream: client.events)

        // Запускаем клиента.
        Task { await client.start() }

        // Клиент должен стать `.active` после хэндшейка.
        _ = try await clientProbe.waitFor(timeout: .seconds(10)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        // Хост видит присоединение клиента.
        _ = try await hostProbe.waitFor(timeout: .seconds(5)) {
            if case .participantJoined(let p) = $0 { return p.id == clientID.peerID }; return false
        }

        // Клиент видит host в списке участников (событие из хэндшейка).
        let joinEvents = clientProbe.events.filter {
            if case .participantJoined = $0 { return true }; return false
        }
        #expect(!joinEvents.isEmpty)

        // Обмен сообщениями: хост → клиент.
        let sentMsg = try await host.send(text: "hello from host")
        _ = try await clientProbe.waitFor(timeout: .seconds(5)) {
            if case .messageReceived(let m) = $0 { return m.id == sentMsg.id }; return false
        }

        // Клиент → хост.
        let clientMsg = try await client.send(text: "hello from client")
        _ = try await hostProbe.waitFor(timeout: .seconds(5)) {
            if case .messageReceived(let m) = $0 { return m.id == clientMsg.id }; return false
        }

        // Хост завершает сессию.
        await host.end()

        // Клиент получает `.ended(.hostEnded)`.
        _ = try await clientProbe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.hostEnded)) = $0 { return true }; return false
        }

        // Хост переходит в `.ended(.leftByUser)`.
        _ = try await hostProbe.waitFor(timeout: .seconds(5)) {
            if case .stateChanged(.ended(.leftByUser)) = $0 { return true }; return false
        }
    }

    // MARK: - Тест 2: неверный секрет

    /// Клиент с другим секретом не может установить TLS → получает `.ended`.
    ///
    /// TLS-PSK несовпадение приводит к `.waiting(.tlsFailure)`, а после
    /// `connectTimeout` (5 с) — к `.ended(.hostUnreachable)`.
    @Test("wrongSecret: client ends with .ended due to TLS failure")
    func wrongSecret() async throws {
        let hostSecret = try makeSecret(byte: 0xAA)
        let clientSecret = try makeSecret(byte: 0xBB)
        let hostID = LocalIdentity.makeTest(nickname: "Host")
        let clientID = LocalIdentity.makeTest(nickname: "ClientWrong")

        let tap = ListenerTap()
        let host = makeHostSession(identity: hostID, secret: hostSecret, tap: tap)
        let hostProbe = EventProbe<SessionEvent>(stream: host.events)

        Task { await host.start() }
        _ = try await hostProbe.waitFor(timeout: .seconds(10)) {
            if case .stateChanged(.active) = $0 { return true }; return false
        }

        let port = try await tap.waitForPort()
        let client = makeClientSession(
            identity: clientID,
            invite: host.invite,
            secret: clientSecret,
            port: port
        )
        let clientProbe = EventProbe<SessionEvent>(stream: client.events)

        Task { await client.start() }

        // Клиент должен закончить с каким-либо .ended (конкретная причина зависит от ОС).
        _ = try await clientProbe.waitFor(timeout: .seconds(15)) {
            if case .stateChanged(.ended) = $0 { return true }; return false
        }
        let ended = clientProbe.events.contains {
            if case .stateChanged(.ended) = $0 { return true }; return false
        }
        #expect(ended)

        // Завершаем хост, чтобы не оставить висящий листенер.
        await host.end()
    }
}

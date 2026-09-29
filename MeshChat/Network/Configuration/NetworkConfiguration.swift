// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Настройки сетевого слоя — тип сервиса, лимиты и все таймауты (§9.4).
///
/// Внедряется через зависимость; в тестах используются короткие значения.
nonisolated struct NetworkConfiguration: Sendable {

    /// Тип Bonjour-сервиса. Одинаков у всех экземпляров приложения.
    let serviceType: String

    /// Максимальное число одновременно подключённых клиентов.
    let maxClients: Int

    /// Таймаут первичного подключения клиента до `.ready`.
    let connectTimeout: Duration

    /// Таймаут ожидания хэндшейка (`clientHello` / `hostWelcome`).
    let handshakeTimeout: Duration

    /// Интервал отправки `ping` от клиента к хосту.
    let heartbeatInterval: Duration

    /// Порог тишины: отсутствие входящих пакетов дольше этого значения — сигнал потери связи.
    let silenceTimeout: Duration

    /// Грейс-период: время, в течение которого клиент ожидает восстановления соединения.
    let reconnectGracePeriod: Duration

    /// Паузы между попытками переподключения клиента.
    let reconnectBackoff: [Duration]

    /// Таймаут на отправку `sessionEnded` перед закрытием всех соединений.
    let sessionEndFlushTimeout: Duration

    /// Стандартная конфигурация для продуктивной сборки (§9.4).
    static let standard = NetworkConfiguration(
        serviceType: "_meshchat._tcp",
        maxClients: 4,
        connectTimeout: .seconds(15),
        handshakeTimeout: .seconds(10),
        heartbeatInterval: .seconds(5),
        silenceTimeout: .seconds(12),
        reconnectGracePeriod: .seconds(20),
        reconnectBackoff: [.seconds(1), .seconds(2), .seconds(4)],
        sessionEndFlushTimeout: .seconds(1)
    )
}

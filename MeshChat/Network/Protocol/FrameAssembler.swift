// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Собирает полные кадры из произвольно нарезанных TCP-чанков (§8.1).
///
/// Формат кадра: 4 байта длины big-endian (только JSON-тело, без самого заголовка)
/// + N байт UTF-8 JSON.
///
/// Буфер не копируется квадратично: хранится пара (буфер, readOffset).
/// Когда `readOffset > buffer.count / 2`, потреблённые байты выбрасываются одним `removeSubrange`.
nonisolated struct FrameAssembler: Sendable {

    /// Максимальная длина JSON-тела кадра в байтах (§8.1).
    static let maxFrameLength = 65_536

    private var buffer = Data()
    private var readOffset = 0

    /// Добавляет полученные байты и возвращает все полные кадры (JSON-тело без 4-байтового заголовка).
    ///
    /// Выброс `PacketCodecError.invalidFrameLength(n)` если заголовок содержит 0 или значение > 65 536.
    /// Возвращённые `Data`-значения гарантированно начинаются с `startIndex == 0`.
    nonisolated mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(contentsOf: chunk)

        var frames: [Data] = []

        while true {
            let available = buffer.count - readOffset

            // Читаем заголовок побайтно (§8.1, избегаем UnsafeRawPointer.load)
            guard available >= 4 else { break }

            let b0 = buffer[buffer.startIndex + readOffset]
            let b1 = buffer[buffer.startIndex + readOffset + 1]
            let b2 = buffer[buffer.startIndex + readOffset + 2]
            let b3 = buffer[buffer.startIndex + readOffset + 3]

            let length = (UInt32(b0) << 24)
                       | (UInt32(b1) << 16)
                       | (UInt32(b2) << 8)
                       |  UInt32(b3)
            let bodyLength = Int(length)

            guard bodyLength > 0, bodyLength <= FrameAssembler.maxFrameLength else {
                throw PacketCodecError.invalidFrameLength(bodyLength)
            }

            guard available >= 4 + bodyLength else { break }

            // Копируем тело в отдельный Data со startIndex == 0 (§8.1)
            let bodyStart = buffer.startIndex + readOffset + 4
            let bodyEnd   = bodyStart + bodyLength
            let frame = Data(buffer[bodyStart..<bodyEnd])
            frames.append(frame)

            readOffset += 4 + bodyLength

            // Уплотняем буфер, если потреблено более половины
            if readOffset > buffer.count / 2 {
                buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + readOffset))
                readOffset = 0
            }
        }

        return frames
    }
}

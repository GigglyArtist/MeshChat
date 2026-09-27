// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation

/// Ошибки кодека протокола (§8.6).
nonisolated enum PacketCodecError: Error, Sendable, Equatable {
    /// Длина кадра равна 0 или превышает `FrameAssembler.maxFrameLength`.
    case invalidFrameLength(Int)
    /// JSON недействителен или в нём нет обязательных полей `v` / `type`.
    case malformedJSON
    /// Поле `v` в конверте не равно `PacketCodec.protocolVersion`.
    case unsupportedVersion(Int)
    /// Поле `type` не распознано (неизвестный пакет).
    case unknownType(String)
}

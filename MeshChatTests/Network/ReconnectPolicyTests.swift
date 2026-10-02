// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 MeshChat contributors

import Foundation
import Testing
@testable import MeshChat

@Suite("ReconnectPolicy")
struct ReconnectPolicyTests {

    @Test("single-element backoff always returns the same delay")
    func singleElement() {
        let policy = ReconnectPolicy(backoff: [.seconds(3)])
        #expect(policy.delay(forAttempt: 1) == .seconds(3))
        #expect(policy.delay(forAttempt: 2) == .seconds(3))
        #expect(policy.delay(forAttempt: 100) == .seconds(3))
    }

    @Test("multi-element: attempts within range use their index")
    func multiElement() {
        let policy = ReconnectPolicy(backoff: [.seconds(1), .seconds(2), .seconds(4)])
        #expect(policy.delay(forAttempt: 1) == .seconds(1))
        #expect(policy.delay(forAttempt: 2) == .seconds(2))
        #expect(policy.delay(forAttempt: 3) == .seconds(4))
    }

    @Test("attempts beyond backoff.count clamp to last element")
    func clampToLast() {
        let policy = ReconnectPolicy(backoff: [.seconds(1), .seconds(2), .seconds(4)])
        #expect(policy.delay(forAttempt: 4) == .seconds(4))
        #expect(policy.delay(forAttempt: 10) == .seconds(4))
        #expect(policy.delay(forAttempt: 100) == .seconds(4))
    }

    @Test(".reliability config backoff produces [50, 100, 200, 200…] ms")
    func reliabilityConfigBackoff() {
        let policy = ReconnectPolicy(backoff: NetworkConfiguration.reliability.reconnectBackoff)
        #expect(policy.delay(forAttempt: 1) == .milliseconds(50))
        #expect(policy.delay(forAttempt: 2) == .milliseconds(100))
        #expect(policy.delay(forAttempt: 3) == .milliseconds(200))
        #expect(policy.delay(forAttempt: 4) == .milliseconds(200))
        #expect(policy.delay(forAttempt: 99) == .milliseconds(200))
    }
}

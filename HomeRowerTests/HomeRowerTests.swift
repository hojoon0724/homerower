import Foundation
import Testing
@testable import HomeRower

/// Feeds scripted key sequences into `HoldTapEngine` and collects what it does.
private struct Harness {
    var engine = HoldTapEngine()
    /// Everything the engine did, excluding timer requests.
    var actions: [EngineAction] = []
    /// Timer token → absolute time it should fire.
    var timers: [Int: TimeInterval] = [:]

    mutating func down(_ keyCode: UInt16, at time: TimeInterval) {
        record(engine.handle(KeyEvent(keyCode: keyCode, isDown: true, timestamp: time)), at: time)
    }

    mutating func up(_ keyCode: UInt16, at time: TimeInterval) {
        record(engine.handle(KeyEvent(keyCode: keyCode, isDown: false, timestamp: time)), at: time)
    }

    /// Fires every timer that is due by `time`, in deadline order.
    mutating func advance(to time: TimeInterval) {
        while let (token, deadline) = timers.min(by: { $0.value < $1.value }), deadline <= time {
            timers[token] = nil
            record(engine.timerFired(token: token, at: deadline), at: deadline)
        }
    }

    private mutating func record(_ result: [EngineAction], at time: TimeInterval) {
        for action in result {
            if case let .startTimer(token, delay) = action {
                timers[token] = time + delay
            } else {
                actions.append(action)
            }
        }
    }
}

// Shorthands for expected actions.
private func tap(_ keyCode: UInt16) -> [EngineAction] {
    [.key(keyCode, down: true), .key(keyCode, down: false)]
}
private func press(_ keyCode: UInt16) -> EngineAction { .key(keyCode, down: true) }
private func release(_ keyCode: UInt16) -> EngineAction { .key(keyCode, down: false) }

/// Start well after "time zero" so the typing-speed rule never kicks in unexpectedly.
private let t0: TimeInterval = 100

struct HoldTapEngineTests {
    @Test func quickTapTypesLetter() {
        var h = Harness()
        h.down(KeyCode.a, at: t0)
        h.up(KeyCode.a, at: t0 + 0.100)
        #expect(h.actions == tap(KeyCode.a))
    }

    @Test func longPressIsModifierOnly() {
        var h = Harness()
        h.down(KeyCode.a, at: t0)
        h.advance(to: t0 + 0.250)
        h.up(KeyCode.a, at: t0 + 0.250)
        #expect(h.actions == [.modifier(.leftShift, down: true), .modifier(.leftShift, down: false)])
    }

    @Test func longPressWithoutTimerStillHolds() {
        // The timer may not have fired yet when the next event arrives.
        var h = Harness()
        h.down(KeyCode.a, at: t0)
        h.up(KeyCode.a, at: t0 + 0.250)
        #expect(h.actions == [.modifier(.leftShift, down: true), .modifier(.leftShift, down: false)])
    }

    @Test func opposideHandRollTypesBothLetters() {
        // A↓ J↓ A↑ J↑ → "ah"
        var h = Harness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.j, at: t0 + 0.050)
        h.up(KeyCode.a, at: t0 + 0.100)
        h.up(KeyCode.j, at: t0 + 0.150)
        #expect(h.actions == tap(KeyCode.a) + tap(KeyCode.j))
    }

    @Test func permissiveHoldGivesShiftedKey() {
        // A↓ J↓ J↑ A↑ → Shift+J
        var h = Harness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.j, at: t0 + 0.050)
        h.up(KeyCode.j, at: t0 + 0.100)
        h.up(KeyCode.a, at: t0 + 0.150)
        #expect(h.actions == [.modifier(.leftShift, down: true)] + tap(KeyCode.j) + [.modifier(.leftShift, down: false)])
    }

    @Test func permissiveHoldWithNonHomeRowKey() {
        // A↓ P↓ P↑ A↑ → Shift+P
        var h = Harness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.p, at: t0 + 0.050)
        h.up(KeyCode.p, at: t0 + 0.100)
        h.up(KeyCode.a, at: t0 + 0.150)
        #expect(h.actions == [.modifier(.leftShift, down: true)] + tap(KeyCode.p) + [.modifier(.leftShift, down: false)])
    }

    @Test func sameHandHomeRowRollTypesBothLetters() {
        // A↓ S↓ S↑ A↑ (same hand) → "ao"
        var h = Harness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.s, at: t0 + 0.050)
        h.up(KeyCode.s, at: t0 + 0.100)
        h.up(KeyCode.a, at: t0 + 0.150)
        #expect(h.actions == [press(KeyCode.a)] + tap(KeyCode.s) + [release(KeyCode.a)])
    }

    @Test func sameHandRollReleasedInOrder() {
        // F↓ D↓ F↑ D↑ → "ue"
        var h = Harness()
        h.down(KeyCode.f, at: t0)
        h.down(KeyCode.d, at: t0 + 0.050)
        h.up(KeyCode.f, at: t0 + 0.100)
        h.up(KeyCode.d, at: t0 + 0.150)
        #expect(h.actions == tap(KeyCode.f) + tap(KeyCode.d))
    }

    @Test func sameHandNonModKeyForcesTap() {
        // A↓ E↓ → A is a tap as soon as E goes down.
        var h = Harness()
        h.down(KeyCode.a, at: t0)
        h.down(KeyCode.e, at: t0 + 0.050)
        #expect(h.actions == [press(KeyCode.a), press(KeyCode.e)])
        h.up(KeyCode.e, at: t0 + 0.100)
        h.up(KeyCode.a, at: t0 + 0.150)
        #expect(h.actions == [press(KeyCode.a), press(KeyCode.e), .passThrough, .passThrough])
    }

    @Test func typingSpeedRuleTapsImmediately() {
        // X↓ X↑, then A↓ within 150 ms, J↓ J↑ A↑ → "xah", no modifiers, all passed through.
        var h = Harness()
        h.down(KeyCode.x, at: t0)
        h.up(KeyCode.x, at: t0 + 0.050)
        h.down(KeyCode.a, at: t0 + 0.100)
        h.down(KeyCode.j, at: t0 + 0.150)
        h.up(KeyCode.j, at: t0 + 0.200)
        h.up(KeyCode.a, at: t0 + 0.250)
        #expect(h.actions == Array(repeating: .passThrough, count: 6))
        #expect(h.timers.isEmpty)
    }

    @Test func stackedModifiersCommandShiftQ() {
        // F↓ A↓ (hold) Q↓ Q↑ → Cmd+Shift+Q
        var h = Harness()
        h.down(KeyCode.f, at: t0)
        h.down(KeyCode.a, at: t0 + 0.050)
        h.advance(to: t0 + 0.300)
        h.down(KeyCode.q, at: t0 + 0.300)
        h.up(KeyCode.q, at: t0 + 0.350)
        #expect(h.actions == [
            .modifier(.leftCommand, down: true),
            .modifier(.leftShift, down: true),
            .passThrough,
            .passThrough,
        ])
        #expect(h.engine.activeModifiers == [.leftCommand, .leftShift])
    }

    @Test func heldModifierDisablesTypingSpeedRule() {
        // Hold F (Cmd), then quickly tap J: J must still be decided, not passed through raw.
        var h = Harness()
        h.down(KeyCode.f, at: t0)
        h.advance(to: t0 + 0.250)
        h.down(KeyCode.j, at: t0 + 0.260)
        h.up(KeyCode.j, at: t0 + 0.300)
        h.up(KeyCode.f, at: t0 + 0.350)
        #expect(h.actions == [.modifier(.leftCommand, down: true)] + tap(KeyCode.j) + [.modifier(.leftCommand, down: false)])
    }

    @Test func resetReleasesHeldModifiers() {
        var h = Harness()
        h.down(KeyCode.semicolon, at: t0)
        h.advance(to: t0 + 0.250)
        #expect(h.engine.reset() == [.modifier(.rightShift, down: false)])
        #expect(h.engine.activeModifiers.isEmpty)
    }
}

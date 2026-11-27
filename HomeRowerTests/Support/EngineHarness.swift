import Foundation
@testable import HomeRower

/// Feeds scripted key sequences into `HoldTapEngine` and collects what it does.
struct EngineHarness {
    var engine: HoldTapEngine
    /// Everything the engine did, excluding timer requests.
    var actions: [EngineAction] = []
    /// Timer token → absolute time it should fire.
    var timers: [Int: TimeInterval] = [:]

    init(settings: HoldTapEngine.Settings = .init()) {
        engine = HoldTapEngine(settings: settings)
    }

    mutating func down(_ keyCode: UInt16, at time: TimeInterval) {
        record(engine.handle(KeyEvent(keyCode: keyCode, isDown: true, timestamp: time)), at: time)
    }

    /// An autorepeat key down, as macOS sends while a key is held.
    mutating func repeatDown(_ keyCode: UInt16, at time: TimeInterval) {
        record(engine.handle(KeyEvent(keyCode: keyCode, isDown: true, isRepeat: true, timestamp: time)), at: time)
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

/// A key pressed and released.
func tap(_ keyCode: UInt16) -> [EngineAction] {
    [.key(keyCode, down: true), .key(keyCode, down: false)]
}

func press(_ keyCode: UInt16) -> EngineAction { .key(keyCode, down: true) }

func release(_ keyCode: UInt16) -> EngineAction { .key(keyCode, down: false) }

/// Start well after "time zero" so the typing-speed rule never kicks in unexpectedly.
let t0: TimeInterval = 100

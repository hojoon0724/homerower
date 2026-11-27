import Foundation

/// A physical key event as seen by the engine.
nonisolated struct KeyEvent: Equatable, Sendable {
    var keyCode: UInt16
    var isDown: Bool
    var isRepeat: Bool = false
    var timestamp: TimeInterval
}

/// What the engine wants the caller to do. Anything not passed through is swallowed.
nonisolated enum EngineAction: Equatable, Sendable {
    /// Let the current physical event through unchanged (apart from active modifier flags).
    case passThrough
    /// Post a synthetic key event.
    case key(UInt16, down: Bool, isRepeat: Bool = false)
    /// Press or release a synthetic modifier.
    case modifier(Modifier, down: Bool)
    /// Call `timerFired(token:at:)` after `delay` seconds.
    case startTimer(token: Int, delay: TimeInterval)
}

/// QMK-style hold-tap state machine for home-row mods.
///
/// Pure logic with no CoreGraphics dependency: feed it key events with timestamps
/// and it returns the actions to perform.
nonisolated struct HoldTapEngine {
    struct Settings: Sendable {
        var tappingTerm: TimeInterval = Config.tappingTerm
        var priorIdle: TimeInterval = Config.priorIdle
    }

    private struct Pending {
        var keyCode: UInt16
        var modifier: Modifier
        var downTime: TimeInterval
        var token: Int
    }

    var settings: Settings

    private var pending: Pending?
    /// Events swallowed while `pending` is undecided, in arrival order.
    private var buffer: [KeyEvent] = []
    /// Physical key → modifier it is currently holding down.
    private var heldModifiers: [UInt16: Modifier] = [:]
    /// Time of the last live key event (typing-speed rule).
    private var lastEventTime: TimeInterval?
    private var nextToken = 0
    private var output: [EngineAction] = []

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Modifiers currently held by home-row keys.
    var activeModifiers: Set<Modifier> { Set(heldModifiers.values) }

    // MARK: - Inputs

    /// Handles a live key event from the keyboard.
    mutating func handle(_ event: KeyEvent) -> [EngineAction] {
        output = []
        process(event, now: event.timestamp, isLive: true)
        lastEventTime = event.timestamp

        // If the only result is the event itself, pass the original through instead of
        // re-posting it. Anything more complex is posted so the order is preserved.
        if output == [.key(event.keyCode, down: event.isDown, isRepeat: event.isRepeat)] {
            return [.passThrough]
        }
        return output
    }

    /// Handles a fired `tappingTerm` timer. Stale tokens are ignored.
    mutating func timerFired(token: Int, at time: TimeInterval) -> [EngineAction] {
        output = []
        if let pending, pending.token == token {
            resolveHold(trigger: nil, now: time)
        }
        return output
    }

    /// Drops all state and releases any held modifiers (used when disabling the app).
    mutating func reset() -> [EngineAction] {
        let releases = heldModifiers.values.map { EngineAction.modifier($0, down: false) }
        pending = nil
        buffer = []
        heldModifiers = [:]
        lastEventTime = nil
        return releases
    }

    // MARK: - Processing

    private mutating func process(_ event: KeyEvent, now: TimeInterval, isLive: Bool) {
        // The tapping term may have run out before this event happened, even if the
        // timer hasn't fired yet (or the event is being replayed). Decide that first.
        if let pending, event.timestamp >= pending.downTime + settings.tappingTerm {
            resolveHold(trigger: nil, now: now)
        }

        if pending != nil {
            processWhilePending(event, now: now)
            return
        }

        if event.isDown {
            if event.isRepeat {
                // Autorepeat of a key that is acting as a modifier: swallow.
                if heldModifiers[event.keyCode] == nil { emit(event) }
                return
            }
            if let modifier = Config.homeRowMods[event.keyCode], heldModifiers[event.keyCode] == nil {
                // Typing-speed rule: pressed right after another key while typing → tap.
                if isLive, heldModifiers.isEmpty, let lastEventTime,
                   event.timestamp - lastEventTime < settings.priorIdle {
                    emit(event)
                    return
                }
                startPending(keyCode: event.keyCode, modifier: modifier, downTime: event.timestamp, now: now)
                return
            }
            emit(event)
        } else {
            if let modifier = heldModifiers.removeValue(forKey: event.keyCode) {
                output.append(.modifier(modifier, down: false))
                return
            }
            emit(event)
        }
    }

    private mutating func processWhilePending(_ event: KeyEvent, now: TimeInterval) {
        guard let pending else { return }

        if event.keyCode == pending.keyCode {
            // Autorepeat of the pending key: swallow.
            guard !event.isDown else { return }
            // Released before anything decided it → tap.
            self.pending = nil
            output.append(.key(pending.keyCode, down: true))
            output.append(.key(pending.keyCode, down: false))
            replayBuffer(now: now)
            return
        }

        if event.isRepeat {
            buffer.append(event)
            return
        }

        let sameHand = isSameHand(event.keyCode, pending.keyCode)
        let isHomeRowMod = Config.homeRowMods[event.keyCode] != nil

        if event.isDown {
            // Opposite-hand rule: a same-hand key means we're typing, not chording.
            // Home-row mods on the same hand are exempt so they can stack (e.g. F+A → Cmd+Shift).
            if sameHand && !isHomeRowMod {
                resolveTap(trigger: event, now: now)
            } else {
                buffer.append(event)
            }
            return
        }

        // A key that was pressed *and* released while pending.
        let pressedWhilePending = buffer.contains { $0.keyCode == event.keyCode && $0.isDown && !$0.isRepeat }
        if pressedWhilePending {
            if sameHand && isHomeRowMod {
                // Same-hand roll across two home-row keys (e.g. "ue") → tap.
                resolveTap(trigger: event, now: now)
            } else {
                // Permissive hold.
                resolveHold(trigger: event, now: now)
            }
            return
        }

        buffer.append(event)
    }

    // MARK: - Resolution

    private mutating func startPending(keyCode: UInt16, modifier: Modifier, downTime: TimeInterval, now: TimeInterval) {
        let token = nextToken
        nextToken += 1
        pending = Pending(keyCode: keyCode, modifier: modifier, downTime: downTime, token: token)
        let remaining = max(0, settings.tappingTerm - (now - downTime))
        output.append(.startTimer(token: token, delay: remaining))
    }

    /// Resolves the pending key as a tap. Only its key down is sent; the physical key up
    /// later flows through as a normal event.
    private mutating func resolveTap(trigger: KeyEvent, now: TimeInterval) {
        guard let pending else { return }
        self.pending = nil
        output.append(.key(pending.keyCode, down: true))
        buffer.append(trigger)
        replayBuffer(now: now)
    }

    /// Resolves the pending key as a hold: its modifier stays down until the key goes up.
    private mutating func resolveHold(trigger: KeyEvent?, now: TimeInterval) {
        guard let pending else { return }
        self.pending = nil
        heldModifiers[pending.keyCode] = pending.modifier
        output.append(.modifier(pending.modifier, down: true))
        if let trigger { buffer.append(trigger) }
        replayBuffer(now: now)
    }

    /// Feeds buffered events back through the handler, so a home-row key in the buffer
    /// can become pending itself (this is what makes modifiers stack).
    private mutating func replayBuffer(now: TimeInterval) {
        let events = buffer
        buffer = []
        for event in events {
            process(event, now: now, isLive: false)
        }
    }

    // MARK: - Helpers

    private mutating func emit(_ event: KeyEvent) {
        output.append(.key(event.keyCode, down: event.isDown, isRepeat: event.isRepeat))
    }

    private func isSameHand(_ a: UInt16, _ b: UInt16) -> Bool {
        guard let handA = Config.hand(of: a), let handB = Config.hand(of: b) else { return false }
        return handA == handB
    }
}

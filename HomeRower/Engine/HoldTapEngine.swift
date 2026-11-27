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
        /// Physical key → modifier when held.
        var keyMap: [UInt16: ModifierSet] = Config.homeRowMods
        /// Shift keys are decided only by which key goes up first (or the tapping term),
        /// never by the next key going down. Capitals are typed fast and often with a
        /// same-hand letter, which the typing-speed and opposite-hand rules would turn
        /// into two letters.
        var shiftDecidedByRelease = Config.shiftDecidedByRelease
    }

    private struct Pending {
        var keyCode: UInt16
        var modifiers: ModifierSet
        var downTime: TimeInterval
        var token: Int
        /// Pressed during fast typing (typing-speed rule): only a timeout can make it a hold.
        var isFastTyping: Bool
    }

    /// An event plus whether it arrived during fast typing, decided when it arrived.
    private struct Buffered {
        var event: KeyEvent
        var isFastTyping: Bool
    }

    var settings: Settings

    private var pending: Pending?
    /// Events swallowed while `pending` is undecided, in arrival order.
    private var buffer: [Buffered] = []
    /// Physical key → modifier it is currently holding down.
    private var heldModifiers: [UInt16: ModifierSet] = [:]
    /// Time of the last live key event (typing-speed rule).
    private var lastEventTime: TimeInterval?
    private var nextToken = 0
    private var output: [EngineAction] = []

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Modifiers currently held by home-row keys.
    var activeModifiers: Set<Modifier> { Set(heldModifiers.values.flatMap(\.modifiers)) }

    /// Home-row keys currently held as their modifier.
    var heldKeys: Set<UInt16> { Set(heldModifiers.keys) }

    // MARK: - Inputs

    /// Handles a live key event from the keyboard.
    mutating func handle(_ event: KeyEvent) -> [EngineAction] {
        output = []
        // Typing-speed rule: pressed right after another key, with no modifier held.
        // A key pressed while another home-row key is pending is part of the same
        // chord (e.g. F then D for Cmd+Opt), so it inherits that key's verdict instead.
        var isFastTyping = false
        if let pending {
            isFastTyping = pending.isFastTyping
        } else if heldModifiers.isEmpty, let lastEventTime {
            isFastTyping = event.timestamp - lastEventTime < settings.priorIdle
        }
        process(Buffered(event: event, isFastTyping: isFastTyping), now: event.timestamp)
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
        let releases = heldModifiers.values.flatMap(Self.release)
        pending = nil
        buffer = []
        heldModifiers = [:]
        lastEventTime = nil
        return releases
    }

    // MARK: - Processing

    private mutating func process(_ item: Buffered, now: TimeInterval) {
        let event = item.event

        // The tapping term may have run out before this event happened, even if the
        // timer hasn't fired yet (or the event is being replayed). Decide that first.
        if let pending, event.timestamp >= pending.downTime + settings.tappingTerm {
            resolveHold(trigger: nil, now: now)
        }

        if pending != nil {
            processWhilePending(item, now: now)
            return
        }

        if event.isDown {
            if event.isRepeat {
                // Autorepeat of a key that is acting as a modifier: swallow.
                if heldModifiers[event.keyCode] == nil { emit(event) }
                return
            }
            if let modifiers = settings.keyMap[event.keyCode], !modifiers.isEmpty, heldModifiers[event.keyCode] == nil {
                startPending(
                    keyCode: event.keyCode,
                    modifiers: modifiers,
                    downTime: event.timestamp,
                    isFastTyping: item.isFastTyping,
                    now: now
                )
                return
            }
            emit(event)
        } else {
            if let modifiers = heldModifiers.removeValue(forKey: event.keyCode) {
                output += Self.release(modifiers)
                return
            }
            emit(event)
        }
    }

    private mutating func processWhilePending(_ item: Buffered, now: TimeInterval) {
        guard let pending else { return }
        let event = item.event

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

        let pressedWhilePending = buffer.contains {
            $0.event.keyCode == event.keyCode && $0.event.isDown && !$0.event.isRepeat
        }

        // A key that went down before the pending one: its press is already out, so its
        // repeats and release can't change the decision. Send them now; holding the release
        // back keeps the key down too long (e.g. it opens the accent popup once the
        // modifier lands).
        if !pressedWhilePending && (event.isRepeat || !event.isDown) {
            passEarlierKey(event)
            return
        }

        if event.isRepeat {
            buffer.append(item)
            return
        }

        // Shift, and keys outside the letter block (Caps Lock), aren't typed in rolls:
        // only releases (and the timeout) decide, so skip the rules that decide on a key
        // going down.
        let decidedByRelease = (settings.shiftDecidedByRelease && pending.modifiers.isShiftOnly)
            || Config.hand(of: pending.keyCode) == nil

        // Fast typing: the next key press means this was a letter in a roll. Only
        // holding past the tapping term (the timeout) makes it a modifier.
        if pending.isFastTyping && event.isDown && !decidedByRelease {
            resolveTap(trigger: item, now: now)
            return
        }

        let sameHand = isSameHand(event.keyCode, pending.keyCode)
        let isHomeRowMod = settings.keyMap[event.keyCode] != nil

        if event.isDown {
            // Opposite-hand rule: a same-hand key means we're typing, not chording.
            // Home-row mods on the same hand are exempt so they can stack (e.g. F+A → Cmd+Shift).
            // If the chord already spans both hands (e.g. F+K), every key is on the same hand
            // as one of its mods, so don't treat that as typing.
            if sameHand && !isHomeRowMod && !chordHasModifier(oppositeTo: event.keyCode) && !decidedByRelease {
                resolveTap(trigger: item, now: now)
            } else {
                buffer.append(item)
            }
            return
        }

        // Released here, so it was pressed *and* released while pending.
        if sameHand && isHomeRowMod && !decidedByRelease {
            // Same-hand roll across two home-row keys (e.g. "ue") → tap.
            resolveTap(trigger: item, now: now)
        } else {
            // Permissive hold.
            resolveHold(trigger: item, now: now)
        }
    }

    /// Handles a repeat or release of a key pressed before the pending key, as if nothing
    /// were pending: a held modifier is released, anything else goes straight out.
    private mutating func passEarlierKey(_ event: KeyEvent) {
        if let modifiers = heldModifiers[event.keyCode] {
            // Autorepeat of a key acting as a modifier is swallowed.
            guard !event.isDown else { return }
            heldModifiers[event.keyCode] = nil
            output += Self.release(modifiers)
            return
        }
        emit(event)
    }

    // MARK: - Resolution

    private mutating func startPending(
        keyCode: UInt16,
        modifiers: ModifierSet,
        downTime: TimeInterval,
        isFastTyping: Bool,
        now: TimeInterval
    ) {
        let token = nextToken
        nextToken += 1
        pending = Pending(keyCode: keyCode, modifiers: modifiers, downTime: downTime, token: token, isFastTyping: isFastTyping)
        let remaining = max(0, settings.tappingTerm - (now - downTime))
        output.append(.startTimer(token: token, delay: remaining))
    }

    /// Resolves the pending key as a tap. Only its key down is sent; the physical key up
    /// later flows through as a normal event.
    private mutating func resolveTap(trigger: Buffered, now: TimeInterval) {
        guard let pending else { return }
        self.pending = nil
        output.append(.key(pending.keyCode, down: true))
        buffer.append(trigger)
        replayBuffer(now: now)
    }

    /// Resolves the pending key as a hold: its modifier stays down until the key goes up.
    private mutating func resolveHold(trigger: Buffered?, now: TimeInterval) {
        guard let pending else { return }
        self.pending = nil
        heldModifiers[pending.keyCode] = pending.modifiers
        output += pending.modifiers.modifiers.map { .modifier($0, down: true) }
        if let trigger { buffer.append(trigger) }
        replayBuffer(now: now)
    }

    /// Feeds buffered events back through the handler, so a home-row key in the buffer
    /// can become pending itself (this is what makes modifiers stack).
    private mutating func replayBuffer(now: TimeInterval) {
        let items = buffer
        buffer = []
        for item in items {
            process(item, now: now)
        }
    }

    // MARK: - Helpers

    /// Releases a key's modifiers, in the reverse of the order they went down.
    private static func release(_ modifiers: ModifierSet) -> [EngineAction] {
        modifiers.modifiers.reversed().map { .modifier($0, down: false) }
    }

    private mutating func emit(_ event: KeyEvent) {
        output.append(.key(event.keyCode, down: event.isDown, isRepeat: event.isRepeat))
    }

    /// Whether a home-row key buffered behind the pending one sits on the other hand from `keyCode`.
    private func chordHasModifier(oppositeTo keyCode: UInt16) -> Bool {
        buffer.contains {
            $0.event.isDown && !$0.event.isRepeat
                && settings.keyMap[$0.event.keyCode] != nil
                && !isSameHand($0.event.keyCode, keyCode)
        }
    }

    private func isSameHand(_ a: UInt16, _ b: UInt16) -> Bool {
        guard let handA = Config.hand(of: a), let handB = Config.hand(of: b) else { return false }
        return handA == handB
    }
}

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
    /// Post a synthetic key event, with Shift added to it alone if `isShifted`.
    case key(UInt16, down: Bool, isRepeat: Bool = false, isShifted: Bool = false)
    /// Press or release a synthetic modifier.
    case modifier(Modifier, down: Bool)
    /// Call `timerFired(token:at:)` after `delay` seconds.
    case startTimer(token: Int, delay: TimeInterval)
}

/// QMK-style hold-tap state machine for home-row mods and layer keys.
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
        /// Physical key → number of the layer it switches on while held (1 and up).
        var layerKeys: [UInt16: Int] = [:]
        /// Remaps of each layer, Layer 1 first: physical key → key (and Shift) it acts as.
        var layerRemaps: [[UInt16: KeyStroke]] = []
        /// Physical key → key it acts as on Layer 0, for keys the system doesn't already
        /// remap (including Caps Lock's stand-in → the key Caps Lock acts as).
        var baseRemaps: [UInt16: KeyStroke] = [:]
    }

    private struct Pending {
        var keyCode: UInt16
        /// What a hold does: hold these modifiers, or (when `layer` is set) switch to a layer.
        var modifiers: ModifierSet
        var layer: Int?
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
    /// Layer keys held down with their layer on, oldest first. The newest one's layer is in use.
    private var heldLayers: [(keyCode: UInt16, layer: Int)] = []
    /// Physical key → key it was sent as when it went down, so its repeats and release
    /// match even if the layer changes while it's down.
    private var sentAs: [UInt16: KeyStroke] = [:]
    /// Time of the last live key event (typing-speed rule).
    private var lastEventTime: TimeInterval?
    private var nextToken = 0
    private var output: [EngineAction] = []

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Modifiers currently held by home-row keys.
    var activeModifiers: Set<Modifier> { Set(heldModifiers.values.flatMap(\.modifiers)) }

    /// Keys currently held as their modifier or layer.
    var heldKeys: Set<UInt16> { Set(heldModifiers.keys).union(heldLayers.map(\.keyCode)) }

    /// The layer in use: 0 for the base layer, otherwise the newest held layer key's.
    var activeLayer: Int { heldLayers.last?.layer ?? 0 }

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
        heldLayers = []
        sentAs = [:]
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
                // Autorepeat of a key that is acting as a modifier or layer: swallow.
                if !isHeld(event.keyCode) { emit(event) }
                return
            }
            if !isHeld(event.keyCode), let hold = holdAction(of: event.keyCode) {
                startPending(
                    keyCode: event.keyCode,
                    modifiers: hold.modifiers,
                    layer: hold.layer,
                    downTime: event.timestamp,
                    isFastTyping: item.isFastTyping,
                    now: now
                )
                return
            }
            emit(event)
        } else {
            if releaseHold(of: event.keyCode) { return }
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
            emit(KeyEvent(keyCode: pending.keyCode, isDown: true, timestamp: event.timestamp))
            emit(event)
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

        // Shift, layer keys, and keys outside the letter block (Caps Lock), aren't typed in
        // rolls: only releases (and the timeout) decide, so skip the rules that decide on a
        // key going down.
        let decidedByRelease = (settings.shiftDecidedByRelease && pending.modifiers.isShiftOnly)
            || pending.layer != nil
            || Config.hand(of: pending.keyCode) == nil

        // Fast typing: the next key press means this was a letter in a roll. Only
        // holding past the tapping term (the timeout) makes it a modifier. A layer key is
        // usually another character typed in passing, so this applies to it too.
        if pending.isFastTyping && event.isDown && (!decidedByRelease || pending.layer != nil) {
            resolveTap(trigger: item, now: now)
            return
        }

        let sameHand = isSameHand(event.keyCode, pending.keyCode)
        let isHomeRowMod = isHomeRowMod(event.keyCode)

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
        if isHeld(event.keyCode) {
            // Autorepeat of a key acting as a modifier or layer is swallowed.
            guard !event.isDown else { return }
            releaseHold(of: event.keyCode)
            return
        }
        emit(event)
    }

    // MARK: - Resolution

    private mutating func startPending(
        keyCode: UInt16,
        modifiers: ModifierSet,
        layer: Int?,
        downTime: TimeInterval,
        isFastTyping: Bool,
        now: TimeInterval
    ) {
        let token = nextToken
        nextToken += 1
        pending = Pending(
            keyCode: keyCode,
            modifiers: modifiers,
            layer: layer,
            downTime: downTime,
            token: token,
            isFastTyping: isFastTyping
        )
        let remaining = max(0, settings.tappingTerm - (now - downTime))
        output.append(.startTimer(token: token, delay: remaining))
    }

    /// Resolves the pending key as a tap. Only its key down is sent; the physical key up
    /// later flows through as a normal event.
    private mutating func resolveTap(trigger: Buffered, now: TimeInterval) {
        guard let pending else { return }
        self.pending = nil
        emit(KeyEvent(keyCode: pending.keyCode, isDown: true, timestamp: now))
        buffer.append(trigger)
        replayBuffer(now: now)
    }

    /// Resolves the pending key as a hold: its modifier (or layer) stays on until the key
    /// goes up. Keys pressed while it was undecided are replayed in the new layer.
    private mutating func resolveHold(trigger: Buffered?, now: TimeInterval) {
        guard let pending else { return }
        self.pending = nil
        if let layer = pending.layer {
            heldLayers.append((pending.keyCode, layer))
        } else {
            heldModifiers[pending.keyCode] = pending.modifiers
            output += pending.modifiers.modifiers.map { .modifier($0, down: true) }
        }
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

    /// Sends a key as the key it acts as in the layer in use. A press decides that; its
    /// repeats and release follow the press, whatever layer is in use by then.
    private mutating func emit(_ event: KeyEvent) {
        let stroke: KeyStroke
        if event.isDown && !event.isRepeat {
            stroke = outputKey(for: event.keyCode)
            sentAs[event.keyCode] = stroke
        } else if event.isDown {
            stroke = sentAs[event.keyCode] ?? outputKey(for: event.keyCode)
        } else {
            stroke = sentAs.removeValue(forKey: event.keyCode) ?? outputKey(for: event.keyCode)
        }
        output.append(.key(stroke.keyCode, down: event.isDown, isRepeat: event.isRepeat, isShifted: stroke.isShifted))
    }

    /// The key a physical key acts as in the layer in use: its remap there, or else what it
    /// is on Layer 0.
    private func outputKey(for keyCode: UInt16) -> KeyStroke {
        layerRemap(of: keyCode) ?? settings.baseRemaps[keyCode] ?? KeyStroke(keyCode)
    }

    /// The key the layer in use remaps a physical key to, if it does.
    private func layerRemap(of keyCode: UInt16) -> KeyStroke? {
        let index = activeLayer - 1
        guard settings.layerRemaps.indices.contains(index) else { return nil }
        return settings.layerRemaps[index][keyCode]
    }

    /// What holding a key does in the layer in use, or `nil` if it's a plain key there. A
    /// layer that remaps a key makes it plain; otherwise it keeps its Layer 0 hold. Layer
    /// keys only switch from Layer 0: once a layer is on, they just type, so holding a
    /// second one never moves to another layer.
    private func holdAction(of keyCode: UInt16) -> (modifiers: ModifierSet, layer: Int?)? {
        guard layerRemap(of: keyCode) == nil else { return nil }
        if let layer = settings.layerKeys[keyCode] {
            return activeLayer == 0 ? ([], layer) : nil
        }
        if let modifiers = settings.keyMap[keyCode], !modifiers.isEmpty { return (modifiers, nil) }
        return nil
    }

    /// Whether a key has hold modifiers in the layer in use.
    private func isHomeRowMod(_ keyCode: UInt16) -> Bool {
        holdAction(of: keyCode).map { $0.layer == nil } ?? false
    }

    /// Whether a key is down acting as its modifier or layer.
    private func isHeld(_ keyCode: UInt16) -> Bool {
        heldModifiers[keyCode] != nil || heldLayers.contains { $0.keyCode == keyCode }
    }

    /// Ends a key's hold when it goes up: releases its modifiers or turns its layer off.
    /// Returns `false` if it wasn't held.
    @discardableResult
    private mutating func releaseHold(of keyCode: UInt16) -> Bool {
        if let modifiers = heldModifiers.removeValue(forKey: keyCode) {
            output += Self.release(modifiers)
            return true
        }
        if let index = heldLayers.firstIndex(where: { $0.keyCode == keyCode }) {
            heldLayers.remove(at: index)
            return true
        }
        return false
    }

    /// Whether a home-row key buffered behind the pending one sits on the other hand from `keyCode`.
    private func chordHasModifier(oppositeTo keyCode: UInt16) -> Bool {
        buffer.contains {
            $0.event.isDown && !$0.event.isRepeat
                && isHomeRowMod($0.event.keyCode)
                && !isSameHand($0.event.keyCode, keyCode)
        }
    }

    private func isSameHand(_ a: UInt16, _ b: UInt16) -> Bool {
        guard let handA = Config.hand(of: a), let handB = Config.hand(of: b) else { return false }
        return handA == handB
    }
}

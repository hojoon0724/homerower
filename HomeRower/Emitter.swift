import CoreGraphics

/// Builds and posts CGEvents, and keeps track of the synthetic modifier flags that
/// have to be added to every event while a home-row mod is held.
final class Emitter {
    private let source = CGEventSource(stateID: .privateState)
    private var activeModifiers: Set<Modifier> = []

    /// Modifier state of the real keyboard, updated from physical `flagsChanged` events.
    var hardwareFlags: CGEventFlags = CGEventSource.flagsState(.hidSystemState)

    /// Flags for the currently held synthetic modifiers.
    var syntheticFlags: CGEventFlags {
        activeModifiers.reduce(into: CGEventFlags()) { $0.formUnion($1.flags) }
    }

    /// Adds the synthetic modifier flags to an event that is passing through the tap.
    func applyFlags(to event: CGEvent) {
        guard !activeModifiers.isEmpty else { return }
        event.flags = event.flags.union(syntheticFlags)
    }

    func postKey(_ keyCode: UInt16, down: Bool, isRepeat: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down) else { return }
        event.flags = hardwareFlags.union(syntheticFlags)
        if isRepeat {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        post(event)
    }

    func setModifier(_ modifier: Modifier, down: Bool) {
        if down {
            activeModifiers.insert(modifier)
        } else {
            activeModifiers.remove(modifier)
        }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(modifier.keyCode), keyDown: down) else { return }
        event.type = .flagsChanged
        event.flags = hardwareFlags.union(syntheticFlags)
        post(event)
    }

    /// Releases every synthetic modifier that is still down.
    func releaseAllModifiers() {
        for modifier in activeModifiers {
            setModifier(modifier, down: false)
        }
    }

    private func post(_ event: CGEvent) {
        // Tag the event so the tap recognizes it and lets it through untouched.
        event.setIntegerValueField(.eventSourceUserData, value: Config.syntheticEventTag)
        event.post(tap: .cghidEventTap)
    }
}

private extension Modifier {
    /// Generic flag plus the device-dependent left/right bit (NX_DEVICE*KEYMASK),
    /// since some apps distinguish left and right modifiers.
    var flags: CGEventFlags {
        switch self {
        case .leftShift: [.maskShift, CGEventFlags(rawValue: 0x0000_0002)]
        case .rightShift: [.maskShift, CGEventFlags(rawValue: 0x0000_0004)]
        case .leftControl: [.maskControl, CGEventFlags(rawValue: 0x0000_0001)]
        case .rightControl: [.maskControl, CGEventFlags(rawValue: 0x0000_2000)]
        case .leftOption: [.maskAlternate, CGEventFlags(rawValue: 0x0000_0020)]
        case .rightOption: [.maskAlternate, CGEventFlags(rawValue: 0x0000_0040)]
        case .leftCommand: [.maskCommand, CGEventFlags(rawValue: 0x0000_0008)]
        case .rightCommand: [.maskCommand, CGEventFlags(rawValue: 0x0000_0010)]
        }
    }
}

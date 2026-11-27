import Foundation

/// Which hand a physical key belongs to (used by the opposite-hand rule).
nonisolated enum Hand: Sendable {
    case left
    case right
}

nonisolated enum Config {
    /// Hold if the key is still down after this.
    static let tappingTerm: TimeInterval = 0.200
    /// Typing-speed rule: tap if pressed this soon after the last key event.
    static let priorIdle: TimeInterval = 0.150
    /// Shift home-row keys are decided by release order only (see `HoldTapEngine.Settings`).
    static let shiftDecidedByRelease = true
    /// Tap then hold within this = key repeat (milestone 9, not used yet).
    static let quickTap: TimeInterval = 0.175

    /// The key Caps Lock is remapped to (with `hidutil`) while it has hold modifiers, so the
    /// event tap sees ordinary key presses instead of Caps Lock's toggle. Rarely on keyboards.
    static let capsLockStandIn = KeyCode.f18

    /// Tag written into `.eventSourceUserData` of every event we post, so the tap can ignore them.
    static let syntheticEventTag: Int64 = 0x484D52

    /// Default key map: physical home-row key → modifier when held. The user can change it.
    static let homeRowMods: [UInt16: ModifierSet] = [
        KeyCode.a: .leftShift,
        KeyCode.s: .leftControl,
        KeyCode.d: .leftOption,
        KeyCode.f: .leftCommand,
        KeyCode.j: .rightCommand,
        KeyCode.k: .rightOption,
        KeyCode.l: .rightControl,
        KeyCode.semicolon: .rightShift,
    ]

    static let leftHandKeys: Set<UInt16> = [
        KeyCode.q, KeyCode.w, KeyCode.e, KeyCode.r, KeyCode.t,
        KeyCode.a, KeyCode.s, KeyCode.d, KeyCode.f, KeyCode.g,
        KeyCode.z, KeyCode.x, KeyCode.c, KeyCode.v, KeyCode.b,
    ]

    static let rightHandKeys: Set<UInt16> = [
        KeyCode.y, KeyCode.u, KeyCode.i, KeyCode.o, KeyCode.p, KeyCode.leftBracket,
        KeyCode.h, KeyCode.j, KeyCode.k, KeyCode.l, KeyCode.semicolon, KeyCode.quote,
        KeyCode.n, KeyCode.m, KeyCode.comma, KeyCode.period, KeyCode.slash,
    ]

    /// The hand a key belongs to, or `nil` for keys outside both sets (space, number row, …).
    static func hand(of keyCode: UInt16) -> Hand? {
        if leftHandKeys.contains(keyCode) { return .left }
        if rightHandKeys.contains(keyCode) { return .right }
        return nil
    }
}

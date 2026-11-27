import Foundation

/// Which hand a physical key belongs to (used by the opposite-hand rule).
nonisolated enum Hand: Sendable {
    case left
    case right
}

/// The modifier a home-row key produces when held.
nonisolated enum Modifier: String, CaseIterable, Sendable {
    case leftShift
    case leftControl
    case leftOption
    case leftCommand
    case rightCommand
    case rightOption
    case rightControl
    case rightShift

    /// Virtual key code of the real modifier key (`kVK_Shift`, `kVK_Command`, …).
    var keyCode: UInt16 {
        switch self {
        case .leftShift: 56
        case .leftControl: 59
        case .leftOption: 58
        case .leftCommand: 55
        case .rightCommand: 54
        case .rightOption: 61
        case .rightControl: 62
        case .rightShift: 60
        }
    }
}

/// Physical key codes (`kVK_ANSI_*`). Names are the QWERTY legends, not the Dvorak output.
nonisolated enum KeyCode {
    static let a: UInt16 = 0
    static let s: UInt16 = 1
    static let d: UInt16 = 2
    static let f: UInt16 = 3
    static let h: UInt16 = 4
    static let g: UInt16 = 5
    static let z: UInt16 = 6
    static let x: UInt16 = 7
    static let c: UInt16 = 8
    static let v: UInt16 = 9
    static let b: UInt16 = 11
    static let q: UInt16 = 12
    static let w: UInt16 = 13
    static let e: UInt16 = 14
    static let r: UInt16 = 15
    static let y: UInt16 = 16
    static let t: UInt16 = 17
    static let o: UInt16 = 31
    static let u: UInt16 = 32
    static let leftBracket: UInt16 = 33
    static let i: UInt16 = 34
    static let p: UInt16 = 35
    static let l: UInt16 = 37
    static let j: UInt16 = 38
    static let quote: UInt16 = 39
    static let k: UInt16 = 40
    static let semicolon: UInt16 = 41
    static let comma: UInt16 = 43
    static let slash: UInt16 = 44
    static let n: UInt16 = 45
    static let m: UInt16 = 46
    static let period: UInt16 = 47
}

nonisolated enum Config {
    /// Hold if the key is still down after this.
    static let tappingTerm: TimeInterval = 0.200
    /// Typing-speed rule: tap if pressed this soon after the last key event.
    static let priorIdle: TimeInterval = 0.150
    /// Tap then hold within this = key repeat (milestone 9, not used yet).
    static let quickTap: TimeInterval = 0.175

    /// Tag written into `.eventSourceUserData` of every event we post, so the tap can ignore them.
    static let syntheticEventTag: Int64 = 0x484D52

    /// Physical home-row key → modifier when held.
    static let homeRowMods: [UInt16: Modifier] = [
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

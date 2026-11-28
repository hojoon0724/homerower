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

    /// Virtual key code of the real modifier key.
    var keyCode: UInt16 {
        switch self {
        case .leftShift: KeyCode.leftShift
        case .leftControl: KeyCode.leftControl
        case .leftOption: KeyCode.leftOption
        case .leftCommand: KeyCode.leftCommand
        case .rightCommand: KeyCode.rightCommand
        case .rightOption: KeyCode.rightOption
        case .rightControl: KeyCode.rightControl
        case .rightShift: KeyCode.rightShift
        }
    }

    var displayName: String {
        switch self {
        case .leftShift: "Left Shift"
        case .leftControl: "Left Control"
        case .leftOption: "Left Option"
        case .leftCommand: "Left Command"
        case .rightCommand: "Right Command"
        case .rightOption: "Right Option"
        case .rightControl: "Right Control"
        case .rightShift: "Right Shift"
        }
    }

    var symbol: String {
        switch self {
        case .leftShift, .rightShift: "⇧"
        case .leftControl, .rightControl: "⌃"
        case .leftOption, .rightOption: "⌥"
        case .leftCommand, .rightCommand: "⌘"
        }
    }

    var isLeft: Bool {
        switch self {
        case .leftShift, .leftControl, .leftOption, .leftCommand: true
        case .rightShift, .rightControl, .rightOption, .rightCommand: false
        }
    }

    /// The name without its side, e.g. "Shift".
    var kindName: String {
        switch self {
        case .leftShift, .rightShift: "Shift"
        case .leftControl, .rightControl: "Control"
        case .leftOption, .rightOption: "Option"
        case .leftCommand, .rightCommand: "Command"
        }
    }

    var isShift: Bool { self == .leftShift || self == .rightShift }

    /// The order macOS shows modifiers in (⌃ ⌥ ⇧ ⌘), left before right.
    static let displayOrder: [Modifier] = [
        .leftShift, leftControl,leftOption,leftCommand,
        .rightCommand,rightOption,rightControl,rightShift
    ]

    /// Which side of the keyboard the modifier is on, shown next to the symbol on a key cap.
    var side: String { isLeft ? "Left" : "Right" }
}

/// The modifiers a key holds down together, e.g. ⇧⌘. Single modifiers read the same as
/// `Modifier` cases: `.leftShift`, or `[.leftShift, .leftCommand]` for a combination.
nonisolated struct ModifierSet: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(_ modifier: Modifier) {
        // `allCases` order is part of the raw value, but the raw value is never saved.
        rawValue = 1 << UInt8(Modifier.allCases.firstIndex(of: modifier) ?? 0)
    }

    init(_ modifiers: some Sequence<Modifier>) {
        self = modifiers.reduce(into: []) { $0.insert(ModifierSet($1)) }
    }

    static let leftShift = ModifierSet(Modifier.leftShift)
    static let leftControl = ModifierSet(Modifier.leftControl)
    static let leftOption = ModifierSet(Modifier.leftOption)
    static let leftCommand = ModifierSet(Modifier.leftCommand)
    static let rightCommand = ModifierSet(Modifier.rightCommand)
    static let rightOption = ModifierSet(Modifier.rightOption)
    static let rightControl = ModifierSet(Modifier.rightControl)
    static let rightShift = ModifierSet(Modifier.rightShift)

    /// The modifiers in the order macOS shows them (⌃ ⌥ ⇧ ⌘).
    var modifiers: [Modifier] {
        Modifier.displayOrder.filter(contains)
    }

    func contains(_ modifier: Modifier) -> Bool {
        contains(ModifierSet(modifier))
    }

    /// Only Shift (either side), which types capitals and gets its own timing rules.
    var isShiftOnly: Bool {
        !isEmpty && modifiers.allSatisfy(\.isShift)
    }
}

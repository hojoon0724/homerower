import CoreGraphics

/// One key on the drawn keyboard.
struct KeySpec: Identifiable {
    let keyCode: UInt16
    /// Fixed legend for non-character keys; character keys are labeled from the input source.
    var legend: String?
    var width: CGFloat = 1

    var id: UInt16 { keyCode }

    /// Only keys with a hand assignment can be home-row-style mods (opposite-hand rule).
    var isMappable: Bool { Config.hand(of: keyCode) != nil }

    struct Row: Identifiable {
        let id: Int
        let keys: [KeySpec]
    }

    /// Keys whose cap shows a symbol rather than a name (⌫, ⇥, ↩).
    private static let symbolKeyCodes: Set<UInt16> = [36, 48, 51]

    /// How to show a key elsewhere in the UI: the same symbol as its key cap where it
    /// has one, otherwise its name.
    static func displayName(for keyCode: UInt16) -> String {
        if symbolKeyCodes.contains(keyCode),
           let legend = rows.lazy.flatMap(\.keys).first(where: { $0.keyCode == keyCode })?.legend {
            return legend
        }
        return KeyNames.name(for: keyCode)
    }

    /// Width of every row, in key units.
    static let rowWidth: CGFloat = 14.5

    /// ANSI MacBook layout by virtual key code.
    static let rows: [Row] = [
        Row(id: 0, keys: [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24].map { KeySpec(keyCode: $0) }
            + [KeySpec(keyCode: 51, legend: "⌫", width: 1.5)]),
        Row(id: 1, keys: [KeySpec(keyCode: 48, legend: "⇥", width: 1.5)]
            + [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42].map { KeySpec(keyCode: $0) }),
        Row(id: 2, keys: [KeySpec(keyCode: 57, legend: "⇪", width: 1.75)]
            + [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39].map { KeySpec(keyCode: $0) }
            + [KeySpec(keyCode: 36, legend: "↩", width: 1.75)]),
        Row(id: 3, keys: [KeySpec(keyCode: 56, legend: "⇧", width: 2.25)]
            + [6, 7, 8, 9, 11, 45, 46, 43, 47, 44].map { KeySpec(keyCode: $0) }
            + [KeySpec(keyCode: 60, legend: "⇧", width: 2.25)]),
        Row(id: 4, keys: [
            KeySpec(keyCode: 63, legend: "fn"),
            KeySpec(keyCode: 59, legend: "⌃"),
            KeySpec(keyCode: 58, legend: "⌥"),
            KeySpec(keyCode: 55, legend: "⌘", width: 1.25),
            KeySpec(keyCode: 49, legend: "", width: 5),
            KeySpec(keyCode: 54, legend: "⌘", width: 1.25),
            KeySpec(keyCode: 61, legend: "⌥"),
            KeySpec(keyCode: 123, legend: "←"),
            KeySpec(keyCode: 126, legend: "↑↓"),
            KeySpec(keyCode: 124, legend: "→"),
        ]),
    ]
}

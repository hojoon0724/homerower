import Carbon
import SwiftUI

/// A MacBook-style keyboard. Click a letter key to choose the modifier it produces when held.
struct KeyboardView: View {
    @Bindable var eventTap: EventTap
    /// Physical key → what it types with the current input source.
    @State private var labels: [UInt16: String] = [:]
    @State private var selectedKey: UInt16?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let unit = geometry.size.width / KeySpec.rowWidth
                VStack(spacing: 0) {
                    ForEach(KeySpec.rows) { row in
                        HStack(spacing: 0) {
                            ForEach(row.keys) { key in
                                keyButton(key, unit: unit)
                                    .frame(width: key.width * unit, height: unit)
                            }
                        }
                    }
                }
            }
            .aspectRatio(KeySpec.rowWidth / CGFloat(KeySpec.rows.count), contentMode: .fit)

            HStack(alignment: .firstTextBaseline) {
                Text("Click a letter key to choose what it does when held. Keys show what they type with your current input source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Reset to Defaults") {
                    eventTap.resetKeyMapToDefaults()
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
        .onAppear(perform: loadLabels)
    }

    private func keyButton(_ key: KeySpec, unit: CGFloat) -> some View {
        let label = key.legend ?? labels[key.keyCode] ?? ""
        let modifier = eventTap.keyMap[key.keyCode]
        let isPresented = Binding(
            get: { selectedKey == key.keyCode },
            set: { if !$0 { selectedKey = nil } }
        )

        return Button {
            selectedKey = key.keyCode
        } label: {
            KeyCap(label: label, modifier: modifier, isMappable: key.isMappable, unit: unit)
        }
        .buttonStyle(.plain)
        .disabled(!key.isMappable)
        .accessibilityLabel(label)
        .accessibilityValue(modifier.map { "Hold for \($0.displayName)" } ?? "No hold modifier")
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            ModifierPicker(
                keyLabel: label,
                selection: Binding(
                    get: { eventTap.keyMap[key.keyCode] },
                    set: { eventTap.setModifier($0, for: key.keyCode) }
                )
            )
        }
    }

    private func loadLabels() {
        var result: [UInt16: String] = [:]
        for row in KeySpec.rows {
            for key in row.keys where key.legend == nil {
                result[key.keyCode] = KeyLabels.character(for: key.keyCode)?.uppercased()
            }
        }
        labels = result
    }
}

// MARK: - Key cap

private struct KeyCap: View {
    let label: String
    let modifier: Modifier?
    let isMappable: Bool
    let unit: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.15)
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: unit * 0.36, weight: .medium))
            if let modifier {
                Text(modifier.shortLabel)
                    .font(.system(size: unit * 0.24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .foregroundStyle(isMappable ? .primary : .tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(modifier != nil ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            shape.strokeBorder(modifier != nil ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
        }
        .contentShape(shape)
        .padding(unit * 0.05)
    }
}

// MARK: - Modifier picker

private struct ModifierPicker: View {
    let keyLabel: String
    @Binding var selection: Modifier?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When \(keyLabel) is held")
                .font(.headline)
            Picker("Modifier", selection: $selection) {
                Text("Nothing (always types)").tag(Modifier?.none)
                ForEach(Modifier.allCases, id: \.self) { modifier in
                    Text("\(modifier.symbol)  \(modifier.displayName)").tag(Optional(modifier))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
        .padding()
    }
}

// MARK: - Layout

/// One key on the drawn keyboard.
private struct KeySpec: Identifiable {
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

// MARK: - Labels

/// Looks up what a physical key types with the current keyboard input source.
private enum KeyLabels {
    static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data

        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}

// MARK: - Modifier names

extension Modifier {
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

    /// Compact label for a key cap, e.g. "L⇧".
    var shortLabel: String {
        switch self {
        case .leftShift, .leftControl, .leftOption, .leftCommand: "L\(symbol)"
        case .rightShift, .rightControl, .rightOption, .rightCommand: "R\(symbol)"
        }
    }
}

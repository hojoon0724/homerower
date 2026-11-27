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

            Text("Click a letter key to choose what it does when held, or Caps Lock to make it act as another key. Keys show what they type with your current input source; hold modifiers stay on the same physical keys when you switch layouts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            // Relabel the keys whenever the input source changes (e.g. ABC ↔ Dvorak).
            // The key map itself is by physical position, so it doesn't change.
            loadLabels()
            let changes = DistributedNotificationCenter.default().notifications(
                named: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
            )
            for await _ in changes {
                loadLabels()
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: KeySpec, unit: CGFloat) -> some View {
        if key.keyCode == CapsLockRemap.capsLockKeyCode {
            capsLockButton(key, unit: unit)
        } else {
            modifierKeyButton(key, unit: unit)
        }
    }

    private func capsLockButton(_ key: KeySpec, unit: CGFloat) -> some View {
        let targetName = eventTap.capsLockTarget.map { KeyNames.name(for: $0) }
        // When remapped, the key shows the key it now acts as.
        let label = eventTap.capsLockTarget.map { KeySpec.displayName(for: $0) } ?? key.legend ?? ""
        let isPresented = Binding(
            get: { selectedKey == key.keyCode },
            set: { if !$0 { selectedKey = nil } }
        )

        return Button {
            selectedKey = key.keyCode
        } label: {
            KeyCap(label: label, modifier: nil, isRemapped: targetName != nil, isMappable: true, unit: unit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Caps Lock")
        .accessibilityValue(targetName.map { "Acts as \($0)" } ?? "Normal Caps Lock")
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            CapsLockRemapView(eventTap: eventTap)
        }
    }

    private func modifierKeyButton(_ key: KeySpec, unit: CGFloat) -> some View {
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

#Preview("Keyboard") {
    KeyboardView(eventTap: EventTap())
        .padding()
        .frame(width: 600)
}

#Preview("Key Caps") {
    // A few caps at a fixed size, for tuning the key cap layout.
    let unit: CGFloat = 48
    HStack(spacing: 0) {
        KeyCap(label: "A", modifier: .leftShift, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "U", modifier: .leftCommand, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "G", modifier: nil, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "H", modifier: .rightCommand, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "S", modifier: .rightShift, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "Esc", modifier: nil, isRemapped: true, isMappable: true, unit: unit)
            .frame(width: unit * 1.75, height: unit)
        KeyCap(label: "Left ⌃", modifier: nil, isRemapped: true, isMappable: true, unit: unit)
            .frame(width: unit * 1.75, height: unit)
        KeyCap(label: "⇥", modifier: nil, isMappable: false, unit: unit)
            .frame(width: unit * 1.5, height: unit)
    }
    .padding()
}

#Preview("Caps Lock Popover") {
    // Popovers don't open in previews, so show the popover's content directly.
    CapsLockRemapView(eventTap: EventTap())
}

// MARK: - Key cap

private struct KeyCap: View {
    let label: String
    let modifier: Modifier?
    /// The key acts as another key (e.g. Caps Lock → Esc); `label` is that key.
    var isRemapped = false
    let isMappable: Bool
    let unit: CGFloat

    private var isHighlighted: Bool { modifier != nil || isRemapped }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.1)
        // The letter is centered in the space above the modifier line, which sits
        // close to the bottom edge of the key.
        VStack(spacing: -7) {
            Spacer(minLength: 0)
            Text(label)
                .font(.system(size: unit * 0.3, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, unit * 0.08)
                .foregroundStyle(isRemapped ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(isMappable ? .primary : .tertiary))
            Spacer(minLength: 0)
            if let modifier {
                // Side and symbol on one line that never wraps; it shrinks to fit instead.
                // The side label sits on the side it names: "LEFT ⇧" and "⇧ RIGHT".
                HStack(alignment: .center, spacing: 0) {
                    if modifier.isLeft { sideLabel(modifier) }
                    Text(modifier.symbol)
                        .font(.system(size: unit * 0.3, weight: .semibold))
                    if !modifier.isLeft { sideLabel(modifier) }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, unit * 0.02)
            }
        }
        .foregroundStyle(isMappable ? .primary : .tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(isHighlighted ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            shape.strokeBorder(isHighlighted ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
        }
        .contentShape(shape)
        .padding(unit * 0.05)
    }

    private func sideLabel(_ modifier: Modifier) -> some View {
        Text(modifier.side)
            .font(.system(size: max(5, unit * 0.1), weight: .black))
            .textCase(.uppercase)
            .tracking(-0.2)
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

// MARK: - Caps Lock remap

/// Records the next key press and makes Caps Lock act as that key.
private struct CapsLockRemapView: View {
    let eventTap: EventTap
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        // One column: the key field, any error, then the restore button.
        VStack(alignment: .center, spacing: 4) {
            keyField

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                Button {
                    stopRecording()
                    errorMessage = nil
                    if !eventTap.setCapsLockTarget(nil) {
                        errorMessage = "Couldn't restore Caps Lock."
                    }
                } label: {
                    Text("Restore")
                        .frame(maxWidth: .infinity)
                }
                .disabled(eventTap.capsLockTarget == nil)
            }
            .controlSize(.small)
        }
        .padding()
        .frame(width: 160)
        .onDisappear(perform: stopRecording)
    }

    /// Shows the key Caps Lock acts as, like an input field. Clicking it records a new
    /// key; clicking again while recording cancels.
    private var keyField: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return Button {
            if isRecording { stopRecording() } else { startRecording() }
        } label: {
            Group {
                if isRecording {
                    Text("Press key to map…")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(eventTap.capsLockTarget.map { KeySpec.displayName(for: $0) } ?? "Caps Lock")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.horizontal, 8)
            .background(shape.fill(Color(nsColor: .textBackgroundColor)))
            .overlay {
                shape.strokeBorder(
                    isRecording ? Color.accentColor : Color.secondary.opacity(0.35),
                    lineWidth: isRecording ? 2 : 1
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Caps Lock acts as")
        .accessibilityValue(isRecording ? "Recording" : (eventTap.capsLockTarget.map { KeyNames.name(for: $0) } ?? "Caps Lock"))
        .accessibilityHint(isRecording ? "Press a key to map, or click to cancel" : "Click, then press a key to map")
    }

    private func startRecording() {
        errorMessage = nil
        isRecording = true
        // Let keys through the event tap untouched so the raw key is recorded.
        eventTap.isRecordingKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Modifier keys arrive as flagsChanged; only count the press, not the release.
            let keyCode = event.keyCode
            let isPress = event.type != .flagsChanged || Self.isModifierPress(event)
            if isPress {
                MainActor.assumeIsolated { record(keyCode) }
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        eventTap.isRecordingKey = false
    }

    private func record(_ keyCode: UInt16) {
        guard CapsLockRemap.canMap(to: keyCode) else {
            errorMessage = "Caps Lock can't act as \(KeyNames.name(for: keyCode)). Try another key."
            return
        }
        stopRecording()
        if !eventTap.setCapsLockTarget(keyCode) {
            errorMessage = "Couldn't remap Caps Lock."
        }
    }

    private nonisolated static func isModifierPress(_ event: NSEvent) -> Bool {
        let flag: NSEvent.ModifierFlags
        switch event.keyCode {
        case 56, 60: flag = .shift
        case 59, 62: flag = .control
        case 58, 61: flag = .option
        case 55, 54: flag = .command
        case 63: flag = .function
        default: return true // Caps Lock toggles; any change counts as a press.
        }
        return event.modifierFlags.contains(flag)
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

// MARK: - Labels

/// Looks up what a physical key types with the current keyboard input source.
enum KeyLabels {
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

    var isLeft: Bool {
        switch self {
        case .leftShift, .leftControl, .leftOption, .leftCommand: true
        case .rightShift, .rightControl, .rightOption, .rightCommand: false
        }
    }

    /// Which side of the keyboard the modifier is on, shown next to the symbol on a key cap.
    var side: String { isLeft ? "Left" : "Right" }
}

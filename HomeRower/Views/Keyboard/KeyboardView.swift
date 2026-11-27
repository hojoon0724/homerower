import Carbon
import SwiftUI

/// A MacBook-style keyboard. Click a letter key to choose the modifier it produces when held.
struct KeyboardView: View {
    @Bindable var eventTap: EventTap
    /// Physical key → what it types with the current input source.
    @State private var labels: [UInt16: String] = [:]
    @State private var selectedKey: UInt16?
    /// Raw key state, to show where a remapped Caps Lock physically is.
    @State private var physicalKeys = PhysicalKeyMonitor()

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
        // Only watch raw keys while the keyboard is on screen.
        .onAppear { physicalKeys.start() }
        .onDisappear { physicalKeys.stop() }
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
        if key.keyCode == KeyCode.capsLock {
            capsLockButton(key, unit: unit)
        } else {
            modifierKeyButton(key, unit: unit)
        }
    }

    private func capsLockButton(_ key: KeySpec, unit: CGFloat) -> some View {
        let targetName = eventTap.capsLockTarget.map { KeyNames.name(for: $0) }
        // When remapped, the key shows the key it now acts as.
        let label = eventTap.capsLockTarget.map { KeySpec.displayName(for: $0) } ?? key.legend ?? ""

        return Button {
            selectedKey = key.keyCode
        } label: {
            KeyCap(
                label: label,
                modifiers: eventTap.layout.capsLockModifiers,
                hand: .left,
                isRemapped: targetName != nil,
                isMappable: true,
                pressState: pressState(for: key.keyCode),
                unit: unit
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Caps Lock")
        .accessibilityValue(capsLockDescription(targetName: targetName))
        .popover(isPresented: isPopoverPresented(for: key), arrowEdge: .bottom) {
            CapsLockRemapView(eventTap: eventTap)
        }
    }

    private func modifierKeyButton(_ key: KeySpec, unit: CGFloat) -> some View {
        let label = key.legend ?? labels[key.keyCode] ?? ""
        let modifiers = eventTap.keyMap[key.keyCode] ?? []
        let hand = Config.hand(of: key.keyCode)

        return Button {
            selectedKey = key.keyCode
        } label: {
            KeyCap(
                label: label,
                modifiers: modifiers,
                hand: hand,
                isMappable: key.isMappable,
                pressState: pressState(for: key.keyCode),
                unit: unit
            )
        }
        .buttonStyle(.plain)
        .disabled(!key.isMappable)
        .accessibilityLabel(label)
        .accessibilityValue(modifiers.isEmpty
            ? "No hold modifier"
            : "Hold for \(modifiers.modifiers.map(\.displayName).formatted(.list(type: .and)))")
        .popover(isPresented: isPopoverPresented(for: key), arrowEdge: .bottom) {
            ModifierPicker(
                keyLabel: label,
                hand: hand,
                selection: Binding(
                    get: { eventTap.keyMap[key.keyCode] ?? [] },
                    set: { eventTap.setModifiers($0, for: key.keyCode) }
                )
            )
        }
    }

    private func capsLockDescription(targetName: String?) -> String {
        if let targetName { return "Acts as \(targetName)" }
        let modifiers = eventTap.layout.capsLockModifiers
        if modifiers.isEmpty { return "Normal Caps Lock" }
        return "Hold for \(modifiers.modifiers.map(\.displayName).formatted(.list(type: .and))), tap for Caps Lock"
    }

    /// Whether the physical key is up, pressed, or held as its hold modifier.
    private func pressState(for keyCode: UInt16) -> KeyCap.PressState {
        // A remapped Caps Lock reaches the event tap as its target key, so the raw key
        // state decides which of the two was really pressed.
        if let target = eventTap.capsLockTarget, physicalKeys.isWatching,
           keyCode == KeyCode.capsLock || keyCode == target {
            let isCapsLock = keyCode == KeyCode.capsLock
            let isDown = physicalKeys.isDown(keyCode)
            // A hold on the target key belongs to whichever of the two is physically down.
            let holdIsCapsLock = physicalKeys.isDown(KeyCode.capsLock) && !physicalKeys.isDown(target)
            let isHeld = isDown && eventTap.heldKeys.contains(target) && holdIsCapsLock == isCapsLock
            return Self.pressState(isDown: isDown, isHeld: isHeld)
        }
        return Self.pressState(isDown: eventTap.pressedKeys.contains(keyCode), isHeld: eventTap.heldKeys.contains(keyCode))
    }

    private static func pressState(isDown: Bool, isHeld: Bool) -> KeyCap.PressState {
        if isHeld { return .held }
        if isDown { return .pressed }
        return .up
    }

    /// Shows a key's popover while it's the selected key; closing the popover deselects it.
    private func isPopoverPresented(for key: KeySpec) -> Binding<Bool> {
        Binding(
            get: { selectedKey == key.keyCode },
            set: { if !$0 { selectedKey = nil } }
        )
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
    KeyboardView(eventTap: .preview())
        .padding()
        .frame(width: 600)
}

#Preview("Caps Lock Remapped") {
    KeyboardView(eventTap: .preview(capsLockTarget: KeyCode.escape))
        .padding()
        .frame(width: 600)
}

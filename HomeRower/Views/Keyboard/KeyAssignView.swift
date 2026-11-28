import SwiftUI

/// What a key does on Layer 0: act as another key (Remap), or do something when held
/// (Hold) — hold modifiers, or switch to a layer. It's one or the other, and within Hold,
/// modifiers or a layer. A tap of a held key still types it (Caps Lock still toggles).
struct KeyAssignView: View {
    private enum Mode {
        case remap
        case hold
    }

    let eventTap: EventTap
    let keyCode: UInt16
    /// The key as its key cap shows it ("Caps Lock" for Caps Lock).
    let keyLabel: String
    @State private var mode: Mode
    @State private var isRecording: Bool
    @State private var errorMessage: String?

    init(eventTap: EventTap, keyCode: UInt16, keyLabel: String) {
        self.eventTap = eventTap
        self.keyCode = keyCode
        self.keyLabel = keyLabel
        let layout = eventTap.layout
        let isCapsLock = keyCode == KeyCode.capsLock
        let hasHold = isCapsLock
            ? !layout.capsLockModifiers.isEmpty
            : layout.homeRowMods[keyCode] != nil || layout.layerNumber(activatedBy: keyCode) != nil
        let mode: Mode = hasHold || !Layer.canRemap(keyCode) ? .hold : .remap
        _mode = State(initialValue: mode)
        // Opening on Remap starts recording, so the next key pressed is the new key.
        _isRecording = State(initialValue: mode == .remap)
    }

    private var isCapsLock: Bool { keyCode == KeyCode.capsLock }

    /// The hand the key is on, for ordering modifiers. Caps Lock sits on the left.
    private var hand: Hand? { isCapsLock ? .left : Config.hand(of: keyCode) }

    /// Letter keys and Caps Lock can hold modifiers.
    private var canHoldModifiers: Bool { hand != nil }

    private var canRemap: Bool { Layer.canRemap(keyCode) }

    private var canHold: Bool { canHoldModifiers || Layer.canBeLayerKey(keyCode) }

    /// The key it acts as on Layer 0, if remapped.
    private var target: KeyStroke? {
        isCapsLock ? eventTap.capsLockTarget.map { KeyStroke($0) } : eventTap.layout.remaps[keyCode]
    }

    private var modifiers: ModifierSet {
        isCapsLock ? eventTap.layout.capsLockModifiers : eventTap.keyMap[keyCode] ?? []
    }

    /// The layer the key switches to when held, if any.
    private var layerID: Layer.ID? {
        eventTap.layout.layers.first { $0.activationKeys.contains(keyCode) }?.id
    }

    private var hasHold: Bool { !modifiers.isEmpty || layerID != nil }

    var body: some View {
        VStack(spacing: 10) {
            if canRemap && canHold {
                Picker("Key", selection: $mode) {
                    Text("Remap").tag(Mode.remap)
                    Text("Hold").tag(Mode.hold)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: mode) {
                    isRecording = false
                    errorMessage = nil
                }
            }

            switch mode {
            case .remap: remap
            case .hold: hold
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(width: 220)
        .onChange(of: isRecording) {
            if isRecording { errorMessage = nil }
        }
    }

    // MARK: - Remap

    private var remap: some View {
        VStack(spacing: 8) {
            KeyRecordField(
                eventTap: eventTap,
                key: target,
                accessibilityLabel: "\(keyLabel) acts as",
                accessibilityEmptyValue: keyLabel,
                isRecording: $isRecording,
                onRecord: record
            )
            .frame(width: 160)

            if hasHold {
                caption("Choosing a key replaces what holding \(keyLabel) does.")
            }

            Button {
                isRecording = false
                errorMessage = nil
                restore()
            } label: {
                Text("Restore")
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 160)
            .controlSize(.small)
            .disabled(target == nil)
        }
    }

    /// Returns `false` to keep recording after a key it can't act as.
    private func record(_ stroke: KeyStroke) -> Bool {
        if isCapsLock {
            // The system mapping Caps Lock goes through can only make it another key.
            guard CapsLockRemap.canMap(to: stroke.keyCode) else {
                errorMessage = "Caps Lock can't act as \(KeyNames.name(for: stroke.keyCode)). Try another key."
                return false
            }
            if !eventTap.setCapsLockTarget(stroke.keyCode) {
                errorMessage = "Couldn't remap Caps Lock."
            }
            return true
        }
        guard Layer.canActAs(stroke.keyCode) else {
            errorMessage = "\(keyLabel) can't act as \(KeyNames.name(for: stroke.keyCode)). Try another key."
            return false
        }
        eventTap.setRemap(stroke, for: keyCode)
        return true
    }

    private func restore() {
        if isCapsLock {
            if !eventTap.setCapsLockTarget(nil) { errorMessage = "Couldn't restore Caps Lock." }
        } else {
            eventTap.setRemap(nil, for: keyCode)
        }
    }

    // MARK: - Hold

    private var hold: some View {
        VStack(alignment: .leading, spacing: 10) {
            if canHoldModifiers {
                ModifierPicker(
                    keyLabel: keyLabel,
                    hand: hand,
                    selection: Binding(get: { modifiers }, set: setModifiers),
                    nothingChecked: isCapsLock ? "Caps Lock works normally." : nil,
                    isPadded: false
                )
                // A layer key is held down on its own, so it can't hold modifiers too.
                .disabled(layerID != nil)
            } else {
                Text("When \(keyLabel) is held")
                    .font(.headline)
            }

            if Layer.canBeLayerKey(keyCode) {
                if canHoldModifiers { Divider() }
                layerMenu
            }

            caption(holdSummary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var layerMenu: some View {
        Picker("Layer", selection: Binding(
            get: { layerID },
            set: { eventTap.setLayerKey($0, for: keyCode) }
        )) {
            Text("None").tag(Layer.ID?.none)
            ForEach(Array(eventTap.layout.layers.enumerated()), id: \.element.id) { index, layer in
                Text(layerTitle(index: index, layer: layer)).tag(Optional(layer.id))
            }
        }
        .pickerStyle(.menu)
        .disabled(eventTap.layout.layers.isEmpty)
    }

    private func setModifiers(_ modifiers: ModifierSet) {
        errorMessage = nil
        if isCapsLock {
            if !eventTap.setCapsLockModifiers(modifiers) { errorMessage = "Couldn't change Caps Lock." }
        } else {
            eventTap.setModifiers(modifiers, for: keyCode)
        }
    }

    /// "Layer 2", noting the other keys that switch to it too.
    private func layerTitle(index: Int, layer: Layer) -> String {
        let title = "Layer \(index + 1)"
        let others = layer.activationKeys.subtracting([keyCode]).sorted().map { KeySpec.displayName(for: $0) }
        guard !others.isEmpty else { return title }
        return "\(title) (also \(others.joined(separator: " ")))"
    }

    private var holdSummary: String {
        if let number = eventTap.layout.layerNumber(activatedBy: keyCode) {
            return "Hold for Layer \(number); a tap types \(keyLabel). It can't hold modifiers as well."
        }
        if Layer.canBeLayerKey(keyCode) && eventTap.layout.layers.isEmpty {
            return "Add a layer with + above the keyboard to switch to it by holding \(keyLabel)."
        }
        if isCapsLock {
            return eventTap.capsLockTarget.map { "A tap is Caps Lock. Checking a modifier stops it acting as \(KeySpec.displayName(for: $0))." }
                ?? "A tap is Caps Lock."
        }
        if let target {
            return "Choosing a hold stops it acting as \(KeySpec.displayName(for: target))."
        }
        return "A tap types \(keyLabel)."
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// Popovers don't open in previews, so these show the popover's content directly.

#Preview("Letter Key") {
    KeyAssignView(eventTap: .preview(), keyCode: KeyCode.a, keyLabel: "A")
}

#Preview("Caps Lock") {
    KeyAssignView(eventTap: .preview(capsLockModifiers: .leftControl), keyCode: KeyCode.capsLock, keyLabel: "Caps Lock")
}

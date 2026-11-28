import SwiftUI

/// Changes what Caps Lock does: act as another key (recorded from the next key press),
/// or hold modifiers while a tap stays Caps Lock. It can be one or the other, not both.
struct CapsLockRemapView: View {
    private enum Mode {
        case actAsKey
        case holdForModifiers
    }

    let eventTap: EventTap
    @State private var mode: Mode
    @State private var isRecording: Bool
    @State private var errorMessage: String?

    init(eventTap: EventTap) {
        self.eventTap = eventTap
        let mode: Mode = eventTap.layout.capsLockModifiers.isEmpty ? .actAsKey : .holdForModifiers
        _mode = State(initialValue: mode)
        // Opening on Remap starts recording, so the next key pressed is Caps Lock's new key.
        _isRecording = State(initialValue: mode == .actAsKey)
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Caps Lock", selection: $mode) {
                Text("Remap").tag(Mode.actAsKey)
                Text("Hold").tag(Mode.holdForModifiers)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) {
                stopRecording()
                errorMessage = nil
            }
            .onChange(of: isRecording) {
                if isRecording { errorMessage = nil }
            }

            switch mode {
            case .actAsKey: actAsKey
            case .holdForModifiers: holdForModifiers
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(width: 200)
    }

    private var actAsKey: some View {
        // One column: the key field, then the restore button.
        VStack(alignment: .center, spacing: 8) {
            keyField
                .frame(width: 160)

            if !eventTap.layout.capsLockModifiers.isEmpty {
                Text("Choosing a key replaces Caps Lock’s hold modifiers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
                .frame(width: 160)
                .disabled(eventTap.capsLockTarget == nil)
            }
            .frame(width: 200)
            .controlSize(.small)
        }
    }

    private var holdForModifiers: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Caps Lock sits on the left, so the left side's modifiers come first.
            ModifierPicker(
                keyLabel: "Caps Lock",
                hand: .left,
                selection: Binding(
                    get: { eventTap.layout.capsLockModifiers },
                    set: { modifiers in
                        errorMessage = nil
                        if !eventTap.setCapsLockModifiers(modifiers) {
                            errorMessage = "Couldn't change Caps Lock."
                        }
                    }
                ),
                nothingChecked: "Caps Lock works normally."
            )
            Text(eventTap.capsLockTarget.map { "A tap is Caps Lock. Checking a modifier stops it acting as \(KeySpec.displayName(for: $0))." }
                ?? "A tap is Caps Lock.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
        }
    }

    /// Shows the key Caps Lock acts as. Clicking it records a new key.
    private var keyField: some View {
        KeyRecordField(
            eventTap: eventTap,
            key: eventTap.capsLockTarget.map { KeyStroke($0) },
            accessibilityLabel: "Caps Lock acts as",
            accessibilityEmptyValue: "Caps Lock",
            isRecording: $isRecording,
            onRecord: record
        )
    }

    private func stopRecording() {
        isRecording = false
    }

    /// Returns `false` to keep recording after a key Caps Lock can't act as.
    /// Shift is ignored: the system mapping Caps Lock goes through can only make it another key.
    private func record(_ stroke: KeyStroke) -> Bool {
        let keyCode = stroke.keyCode
        guard CapsLockRemap.canMap(to: keyCode) else {
            errorMessage = "Caps Lock can't act as \(KeyNames.name(for: keyCode)). Try another key."
            return false
        }
        if !eventTap.setCapsLockTarget(keyCode) {
            errorMessage = "Couldn't remap Caps Lock."
        }
        return true
    }
}

// Popovers don't open in previews, so these show the popover's content directly.

#Preview("Normal Caps Lock") {
    CapsLockRemapView(eventTap: .preview())
}

#Preview("Acts as Esc") {
    CapsLockRemapView(eventTap: .preview(capsLockTarget: KeyCode.escape))
}

#Preview("Holds Control") {
    CapsLockRemapView(eventTap: .preview(capsLockModifiers: .leftControl))
}

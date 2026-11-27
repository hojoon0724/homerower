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
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var errorMessage: String?

    init(eventTap: EventTap) {
        self.eventTap = eventTap
        _mode = State(initialValue: eventTap.layout.capsLockModifiers.isEmpty ? .actAsKey : .holdForModifiers)
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
        .onDisappear(perform: stopRecording)
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
                } else if let target = eventTap.capsLockTarget {
                    Text(KeySpec.displayName(for: target))
                        .font(.title3)
                        .fontWeight(.semibold)
                } else {
                    // Normal Caps Lock: a placeholder inviting a click, like an empty field.
                    Text("Click here to remap")
                        .font(.body)
                        .foregroundStyle(.secondary)
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
        case KeyCode.leftShift, KeyCode.rightShift: flag = .shift
        case KeyCode.leftControl, KeyCode.rightControl: flag = .control
        case KeyCode.leftOption, KeyCode.rightOption: flag = .option
        case KeyCode.leftCommand, KeyCode.rightCommand: flag = .command
        case KeyCode.function: flag = .function
        default: return true // Caps Lock toggles; any change counts as a press.
        }
        return event.modifierFlags.contains(flag)
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

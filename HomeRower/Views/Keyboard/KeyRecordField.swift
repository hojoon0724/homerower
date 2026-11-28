import SwiftUI

/// Shows a key like an input field. Clicking it records the next key pressed; clicking
/// again while recording cancels.
struct KeyRecordField: View {
    let eventTap: EventTap
    /// The key shown, or `nil` for the placeholder.
    let key: KeyStroke?
    var placeholder = "Click here to remap"
    let accessibilityLabel: String
    /// Read out when there's no key.
    let accessibilityEmptyValue: String
    @Binding var isRecording: Bool
    /// Gets each key pressed while recording, shifted if Shift was held with it. Returns
    /// `true` to stop recording, or `false` to keep waiting (e.g. for a key that can't be
    /// used).
    let onRecord: (KeyStroke) -> Bool
    @State private var monitor: Any?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        Button {
            isRecording.toggle()
        } label: {
            Group {
                if isRecording {
                    Text("Press key to map…")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                } else if let key {
                    Text(KeySpec.displayName(for: key))
                        .font(.title3)
                        .fontWeight(.semibold)
                } else {
                    // Nothing mapped: a placeholder inviting a click, like an empty field.
                    Text(placeholder)
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isRecording ? "Recording" : (key.map { KeyNames.name(for: $0) } ?? accessibilityEmptyValue))
        .accessibilityHint(isRecording ? "Press a key to map, or click to cancel" : "Click, then press a key to map")
        // Initial too, so a popover can open already recording.
        .onChange(of: isRecording, initial: true) {
            if isRecording { startMonitoring() } else { stopMonitoring() }
        }
        .onDisappear {
            stopMonitoring()
            isRecording = false
        }
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        // Let keys through the event tap untouched so the raw key is recorded.
        eventTap.isRecordingKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Modifier keys and fn aren't keys to map to (holding modifiers is set
            // elsewhere), so they're swallowed and recording waits for a real key. Caps
            // Lock also arrives as flagsChanged; any change of it counts as a press.
            let stroke = KeyStroke(
                event.keyCode,
                isShifted: event.type == .keyDown && event.modifierFlags.contains(.shift)
            )
            if event.type != .flagsChanged || stroke.keyCode == KeyCode.capsLock {
                MainActor.assumeIsolated {
                    if onRecord(stroke) { isRecording = false }
                }
            }
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        eventTap.isRecordingKey = false
    }
}

import SwiftUI

/// The main window: status, permissions, timings, key map and a place to try typing.
struct MainView: View {
    @Bindable var eventTap: EventTap
    @Environment(\.openWindow) private var openWindow
    @State private var testText = ""

    var body: some View {
        Form {
            statusSection
            if eventTap.status != .running {
                permissionSection
            }
            timingSection
            keyMapSection
            testSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 560)
        .toolbar {
            Button("Show Log", systemImage: "list.bullet.rectangle") {
                openWindow(id: "log")
            }
        }
        // Show a Dock icon only while this window is open.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            LabeledContent("Status") {
                Label(statusText, systemImage: "circle.fill")
                    .foregroundStyle(statusColor)
            }
            Toggle("Home-row mods enabled", isOn: $eventTap.isEnabled)
                .disabled(eventTap.status != .running)
        }
    }

    private var permissionSection: some View {
        Section("Permissions") {
            Text("HomeRower needs **Input Monitoring** and **Accessibility** access to read and send key events. Turn HomeRower on in Privacy & Security, then click Retry.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Privacy Settings…") {
                    eventTap.openPrivacySettings()
                }
                Button("Retry") {
                    eventTap.start()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var timingSection: some View {
        Section {
            TimingRow(
                title: "Tapping term",
                detail: "A home-row key held longer than this becomes a modifier.",
                value: $eventTap.tappingTermMs,
                range: 100...500
            )
            TimingRow(
                title: "Typing-speed rule",
                detail: "A home-row key pressed this soon after another key is always a letter. 0 turns it off.",
                value: $eventTap.priorIdleMs,
                range: 0...300
            )
        } header: {
            HStack {
                Text("Timing")
                Spacer()
                Button("Reset to Defaults") {
                    eventTap.resetTimingsToDefaults()
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }

    private var keyMapSection: some View {
        Section("Key Map") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Key").fontWeight(.semibold)
                    Text("Tap").fontWeight(.semibold)
                    Text("Hold").fontWeight(.semibold)
                }
                .foregroundStyle(.secondary)
                ForEach(KeyMapEntry.all) { entry in
                    GridRow {
                        Text(entry.physical)
                            .font(.system(.body, design: .monospaced))
                        Text(entry.tap)
                            .font(.system(.body, design: .monospaced))
                        Text(entry.hold)
                    }
                }
            }
        }
    }

    private var testSection: some View {
        Section("Try It") {
            TextEditor(text: $testText)
                .font(.body)
                .frame(minHeight: 80)
            Button("Clear") {
                testText = ""
            }
            .disabled(testText.isEmpty)
        }
    }

    // MARK: - Status

    private var statusText: String {
        switch eventTap.status {
        case .running: eventTap.isEnabled ? "Running" : "Paused"
        case .waitingForPermission: "Waiting for permission"
        case .stopped: "Stopped"
        }
    }

    private var statusColor: Color {
        switch eventTap.status {
        case .running: eventTap.isEnabled ? .green : .yellow
        case .waitingForPermission: .orange
        case .stopped: .red
        }
    }
}

/// A slider plus a numeric field for a millisecond value.
private struct TimingRow: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: $value, format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .onSubmit { value = min(max(value, range.lowerBound), range.upperBound) }
                Text("ms")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: 5)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One row of the key map table (from plan.md).
private struct KeyMapEntry: Identifiable {
    let physical: String
    let tap: String
    let hold: String
    var id: String { physical }

    static let all: [KeyMapEntry] = [
        KeyMapEntry(physical: "A", tap: "a", hold: "Left Shift"),
        KeyMapEntry(physical: "S", tap: "o", hold: "Left Control"),
        KeyMapEntry(physical: "D", tap: "e", hold: "Left Option"),
        KeyMapEntry(physical: "F", tap: "u", hold: "Left Command"),
        KeyMapEntry(physical: "J", tap: "h", hold: "Right Command"),
        KeyMapEntry(physical: "K", tap: "t", hold: "Right Option"),
        KeyMapEntry(physical: "L", tap: "n", hold: "Right Control"),
        KeyMapEntry(physical: ";", tap: "s", hold: "Right Shift"),
    ]
}

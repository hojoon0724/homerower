import SwiftUI

/// The settings shown in the main window once HomeRower is running: status, launch
/// options, timings, key map and a place to try typing.
struct MainView: View {
    @Bindable var eventTap: EventTap
    @Bindable var launchSettings: LaunchSettings
    @Environment(\.openWindow) private var openWindow
    @State private var testText = ""

    var body: some View {
        Form {
            launchSection
            timingSection
            keyMapSection
            testSection
            logSection
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 600, maxHeight: .infinity)
        .toolbar {
            // Status and the on/off switch
            ToolbarItem {
                ZStack(alignment: .trailing) {
                    statusControl(isOn: .constant(true)).hidden()
                    statusControl(isOn: $eventTap.isEnabled)
                }
                // Keep it away from the window's right edge.
                .padding(.trailing, 18)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// status dot and text + on/off switch.
    private func statusControl(isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                ZStack(alignment: .leading) {
                    ForEach(Self.statusTextsShownHere, id: \.self) { text in
                        Text(text).hidden()
                    }
                    Text(statusText)
                        .foregroundStyle(statusColor)
                }
                .font(.subheadline)
            }
            Toggle("Home-row mods enabled", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .fixedSize()
        }
        .fixedSize()
        .help("Home-row mods enabled")
    }

    // MARK: - Sections

    private var launchSection: some View {
        Section {
            Toggle("Launch HomeRower at login", isOn: Binding(
                get: { launchSettings.launchesAtLogin },
                set: { launchSettings.setLaunchesAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            if launchSettings.loginItemNeedsApproval {
                HStack {
                    Text("Allow HomeRower in Login Items so it can start at login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Login Items…") {
                        launchSettings.openLoginItemsSettings()
                    }
                    .controlSize(.small)
                }
            }
            Toggle("Open this window when HomeRower launches", isOn: $launchSettings.opensSettingsAtLaunch)
                .toggleStyle(.checkbox)
        }
        // Login Items can be changed in System Settings, so re-read it whenever the
        // window shows.
        .onAppear { launchSettings.refresh() }
    }

    private var timingSection: some View {
        Section {
            TimingRow(
                title: "Hold threshold",
                detail: "How long to hold a home-row key before it acts as a modifier. Raise it if you rest on keys while typing and get modifiers instead of letters.",
                value: $eventTap.tappingTermMs,
                range: 100...500
            )
            TimingRow(
                title: "Fast-typing window",
                detail: "A home-row key pressed this soon after the previous key is treated as a letter, whatever order you release the keys in; it only becomes a modifier if held for the full hold threshold. Raise it if you get stray capitals or shortcuts while typing fast. 0 turns it off.",
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
        Section {
            KeyboardView(eventTap: eventTap)
        } header: {
            HStack {
                Text("Key Map")
                Spacer()
                Button("Reset to Defaults") {
                    eventTap.resetKeyMapToDefaults()
                }
                .buttonStyle(.link)
                .font(.callout)
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

    private var logSection: some View {
        Section {
            Button("Show Log", systemImage: "list.bullet.rectangle") {
                openWindow(id: "log")
            }
        }
    }

    // MARK: - Status

    /// The statuses this view can show. It's only on screen while the tap is running;
    /// the permission screen covers the other states.
    private static let statusTextsShownHere = ["Running", "Stopped"]

    /// "Stopped" means switched off; the tap not running yet is a separate state.
    private var statusText: String {
        switch eventTap.status {
        case .running: eventTap.isEnabled ? "Running" : "Stopped"
        case .waitingForPermission: "Waiting for permission"
        case .stopped: "Starting…"
        }
    }

    private var statusColor: Color {
        switch eventTap.status {
        case .running: eventTap.isEnabled ? .green : .red
        case .waitingForPermission, .stopped: .orange
        }
    }
}

#Preview {
    MainView(eventTap: EventTap(), launchSettings: LaunchSettings())
        .frame(width: 560, height: 820)
}

/// A name with an info tooltip, and a slider for a millisecond value.
private struct TimingRow: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    /// The slider is being dragged; the value shows only then.
    @State private var isDragging = false

    /// The pointer is over the info icon; its description shows only then.
    @State private var isShowingInfo = false

    var body: some View {
        HStack {
            Text(title)
            // The description shows as soon as the pointer is over the icon. A `.help`
            // tooltip waits for the system's hover delay, so this uses a popover instead.
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .onHover { isShowingInfo = $0 }
                .popover(isPresented: $isShowingInfo, arrowEdge: .bottom) {
                    Text(detail)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 280, alignment: .leading)
                        .padding(12)
                }
                .accessibilityLabel("About \(title)")
                .accessibilityValue(detail)
            Spacer()
            // The value, left of the slider, only while dragging. It's faded out rather
            // than removed, so nothing shifts when it appears.
            Text("\(Int(value)) ms")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .opacity(isDragging ? 1 : 0)
                .accessibilityHidden(true)
            Slider(value: $value, in: range) { editing in
                isDragging = editing
            }
            .labelsHidden()
            .frame(width: 260)
            .accessibilityValue("\(Int(value)) milliseconds")
        }
        .padding(.top, 2)
        .padding(.trailing,4)
    }
}

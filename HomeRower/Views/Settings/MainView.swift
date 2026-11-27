import SwiftUI

/// The settings shown in the main window once HomeRower is running: status, launch
/// options, timings, key map and a place to try typing.
struct MainView: View {
    @Bindable var eventTap: EventTap
    @Bindable var launchSettings: LaunchSettings
    @Environment(\.openWindow) private var openWindow
    @State private var testText = ""
    @State private var isSavingLayout = false
    @State private var isManagingLayouts = false
    /// Save Custom… was chosen in the replace alert.
    @State private var isSavingCustom = false

    var body: some View {
        Form {
            launchSection
            timingSection
            keyMapSection
            testSection
            logSection
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isSavingLayout) {
            SaveLayoutSheet(eventTap: eventTap)
        }
        .sheet(isPresented: $isManagingLayouts) {
            ManageLayoutsSheet(eventTap: eventTap)
        }
        .sheet(isPresented: $isSavingCustom, onDismiss: {
            // Cancelled without saving: the edit doesn't happen.
            eventTap.cancelPendingEdit()
        }) {
            SaveLayoutSheet(eventTap: eventTap, source: .customBeforeEdit)
        }
        .alert("Replace your Custom layout?", isPresented: isConfirmingReplace) {
            Button("Save Custom…") { isSavingCustom = true }
            Button("Replace", role: .destructive) { eventTap.confirmPendingEdit() }
            Button("Cancel", role: .cancel) { eventTap.cancelPendingEdit() }
        } message: {
            Text("Your Custom layout has unsaved changes. Editing “\(eventTap.name(of: eventTap.layoutSelection))” will replace them.")
        }
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
            sectionHeader("Timing", reset: eventTap.resetTimingsToDefaults)
        }
    }

    private var keyMapSection: some View {
        Section("Key Map") {
            Picker("Layout", selection: layoutChoice) {
                ForEach(LayoutPreset.allCases) { preset in
                    Text(preset.displayName).tag(LayoutChoice.layout(.preset(preset)))
                }
                if !eventTap.savedLayouts.isEmpty {
                    Divider()
                    ForEach(eventTap.savedLayouts) { saved in
                        Text(saved.name).tag(LayoutChoice.layout(.saved(saved.id)))
                    }
                }
                // Unsaved edits: appears with the first edit and stays until saved or discarded.
                if eventTap.customLayout != nil {
                    Divider()
                    Text("Custom").tag(LayoutChoice.layout(.custom))
                }
                // Actions, not layouts: picking one opens a sheet and leaves the layout alone.
                Divider()
                Text("Save Layout…").tag(LayoutChoice.saveLayout)
                Text("Manage Layouts…").tag(LayoutChoice.manageLayouts)
            }
            KeyboardView(eventTap: eventTap)
        }
    }

    /// Shows the replace alert while an edit waits for the user, unless they're saving Custom.
    /// The alert's buttons decide what happens to the edit, so dismissing does nothing more.
    private var isConfirmingReplace: Binding<Bool> {
        Binding(
            get: { eventTap.pendingEdit != nil && !isSavingCustom },
            set: { _ in }
        )
    }

    /// An entry in the Layout picker.
    private enum LayoutChoice: Hashable {
        case layout(LayoutSelection)
        case saveLayout
        case manageLayouts
    }

    /// The layout in use; picking another switches to it. The selection never becomes an
    /// action, so the picker keeps showing the real layout.
    private var layoutChoice: Binding<LayoutChoice> {
        Binding(
            get: { .layout(eventTap.layoutSelection) },
            set: { choice in
                switch choice {
                case .layout(let selection): eventTap.select(selection)
                case .saveLayout: isSavingLayout = true
                case .manageLayouts: isManagingLayouts = true
                }
            }
        )
    }

    /// A section title with a Reset to Defaults link on the right.
    private func sectionHeader(_ title: LocalizedStringKey, reset: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button("Reset to Defaults", action: reset)
                .buttonStyle(.link)
                .font(.callout)
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
                openWindow.bringToFront(.log)
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

#Preview("Enabled") {
    MainView(eventTap: .preview(), launchSettings: .preview())
        .frame(width: 560, height: 820)
}

#Preview("Disabled") {
    MainView(eventTap: .preview(isEnabled: false), launchSettings: .preview())
        .frame(width: 560, height: 820)
}

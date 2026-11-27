import SwiftUI

/// Saves a layout. The list's first row is a field for naming a new layout; picking an
/// existing layout below it saves over that one instead.
struct SaveLayoutSheet: View {
    /// What's being saved.
    enum Source {
        /// The layout in use (Save Layout…).
        case current
        /// Custom, before a pending edit replaces it (Save Custom… in the replace alert).
        case customBeforeEdit
    }

    /// A row in the list: the new-layout field, or a layout to save over.
    private enum Row: Hashable {
        case newLayout
        case existing(LayoutSelection)
    }

    var eventTap: EventTap
    var source: Source = .current
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selection: Row? = .newLayout
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Layouts that can be saved over, in menu order.
    private var existing: [LayoutSelection] {
        [.preset(.default)] + eventTap.savedLayouts.map { .saved($0.id) }
    }

    /// The layout being saved over: the selected one, or the one whose name was typed
    /// (ignoring case). `nil` when saving a new layout.
    private var replacing: LayoutSelection? {
        switch selection {
        case .existing(let entry):
            entry
        case .newLayout, nil:
            existing.first {
                eventTap.name(of: $0).localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
            }
        }
    }

    private var target: LayoutSaveTarget? {
        if selection == nil { return nil }
        switch replacing {
        case .preset: return .default
        case .saved(let id): return .saved(id)
        // Also rules out the reserved names None and Custom.
        case .custom, nil: return eventTap.isNameAvailable(trimmedName) ? .newLayout(name: trimmedName) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(source == .current ? "Save Layout" : "Save Custom Layout")
                .font(.headline)
            List(selection: $selection) {
                TextField("Layout name", text: $name, prompt: Text("Layout name…").italic())
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .focused($isNameFocused)
                    .onSubmit(save)
                    .tag(Row.newLayout)
                ForEach(existing, id: \.self) { entry in
                    Text(eventTap.name(of: entry))
                        .tag(Row.existing(entry))
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(minHeight: 160)
            // Clicking into the field selects its row, and selecting the row puts the
            // cursor in the field.
            .onChange(of: isNameFocused) {
                if isNameFocused { selection = .newLayout }
            }
            .onChange(of: selection) {
                if selection == .newLayout { isNameFocused = true }
            }
            .onAppear { isNameFocused = true }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(replacing == nil ? "Save" : "Replace", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(target == nil)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func save() {
        guard let target else { return }
        switch source {
        case .current: eventTap.saveCurrentLayout(as: target)
        case .customBeforeEdit: eventTap.saveCustomLayout(as: target)
        }
        dismiss()
    }
}

/// Lists Default, saved layouts and Custom: pick one to use it, or delete, discard or
/// restore it. None is always there, so it isn't listed.
struct ManageLayoutsSheet: View {
    var eventTap: EventTap
    @Environment(\.dismiss) private var dismiss
    @State private var selection: LayoutSelection?
    @State private var confirming: LayoutSelection?

    /// The managed entries, in menu order.
    private var entries: [LayoutSelection] {
        [.preset(.default)] + eventTap.savedLayouts.map { .saved($0.id) }
            + (eventTap.customLayout == nil ? [] : [.custom])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layouts")
                .font(.headline)
            List(entries, id: \.self, selection: $selection) { entry in
                HStack {
                    Text(eventTap.name(of: entry))
                    Spacer()
                    if let note = note(for: entry) {
                        Text(note)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(entry)
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .contextMenu(forSelectionType: LayoutSelection.self) { _ in
            } primaryAction: { entries in
                // Double-click uses the layout.
                if let entry = entries.first { use(entry) }
            }
            .frame(minHeight: 200)
            HStack {
                Button(removeTitle(for: selection), role: .destructive) {
                    confirming = selection
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canRemove(selection))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use Layout") {
                    if let selection { use(selection) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .alert(
            confirming.map(confirmTitle) ?? "",
            isPresented: Binding(
                get: { confirming != nil },
                set: { if !$0 { confirming = nil } }
            ),
            presenting: confirming
        ) { entry in
            Button(removeTitle(for: entry), role: .destructive) { remove(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(confirmMessage(for: entry))
        }
    }

    // MARK: - Entries

    private func note(for entry: LayoutSelection) -> String? {
        var notes: [String] = []
        if entry == .preset(.default), eventTap.defaultOverride != nil { notes.append("Modified") }
        if entry == .custom { notes.append("Unsaved") }
        if entry == eventTap.layoutSelection { notes.append("In Use") }
        return notes.isEmpty ? nil : notes.joined(separator: " · ")
    }

    private func removeTitle(for entry: LayoutSelection?) -> String {
        switch entry {
        case .preset: "Restore Original"
        case .custom: "Discard"
        case .saved, nil: "Delete"
        }
    }

    private func canRemove(_ entry: LayoutSelection?) -> Bool {
        switch entry {
        case .preset: eventTap.defaultOverride != nil
        case .saved, .custom: true
        case nil: false
        }
    }

    private func confirmTitle(for entry: LayoutSelection) -> String {
        switch entry {
        case .preset: "Restore the original Default?"
        case .custom: "Discard your Custom layout?"
        case .saved: "Delete “\(eventTap.name(of: entry))”?"
        }
    }

    private func confirmMessage(for entry: LayoutSelection) -> String {
        let inUse = entry == eventTap.layoutSelection
        switch entry {
        case .preset:
            return "Your changes to Default will be lost."
        case .custom:
            return "Your unsaved changes will be lost." + (inUse ? " You’ll go back to the layout you started from." : "")
        case .saved:
            return "This can’t be undone." + (inUse ? " You’ll switch to Default." : "")
        }
    }

    private func remove(_ entry: LayoutSelection) {
        switch entry {
        case .preset: eventTap.restoreDefaultLayout()
        case .saved(let id): eventTap.deleteLayout(id: id)
        case .custom: eventTap.discardCustomLayout()
        }
        if !entries.contains(where: { $0 == selection }) { selection = nil }
    }

    private func use(_ entry: LayoutSelection) {
        eventTap.select(entry)
        dismiss()
    }
}

// Sheets don't open in previews, so these show the sheets' content directly.

#Preview("Save Layout") {
    SaveLayoutSheet(eventTap: .previewWithLayouts())
}

#Preview("Save Layout – Nothing Saved Yet") {
    SaveLayoutSheet(eventTap: .previewWithLayouts(savedLayouts: false, modifiedDefault: false))
}

#Preview("Save Custom (from Replace Alert)") {
    SaveLayoutSheet(eventTap: .previewWithLayouts(), source: .customBeforeEdit)
}

#Preview("Manage Layouts") {
    ManageLayoutsSheet(eventTap: .previewWithLayouts())
}

#Preview("Manage Layouts – Only Default") {
    ManageLayoutsSheet(eventTap: .previewWithLayouts(savedLayouts: false, modifiedDefault: false, custom: false))
}

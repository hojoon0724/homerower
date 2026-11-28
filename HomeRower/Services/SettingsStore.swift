import Foundation

/// Reads and writes HomeRower's saved settings in `UserDefaults`.
///
/// The keys are part of the saved format: renaming one loses the user's setting.
nonisolated struct SettingsStore {
    private let defaults: UserDefaults

    /// Uses the standard defaults; tests pass a throwaway suite instead.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Settings for SwiftUI previews, kept apart from the app's so previews can't change them.
    static var preview: SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "HomeRower.Previews") ?? .standard)
    }

    private enum Key {
        static let tappingTermMs = "tappingTermMs"
        static let priorIdleMs = "priorIdleMs"
        static let layout = "layout"
        static let savedLayouts = "savedLayouts"
        static let customLayout = "customLayout"
        static let layoutSelection = "layoutSelection"
        static let customBase = "customBase"
        static let defaultLayout = "defaultLayout"
        /// Replaced by `layout`; only read to bring settings forward.
        static let legacyKeyMap = "keyMap"
        static let legacyCapsLockTarget = "capsLockTarget"
        static let opensSettingsAtLaunch = "opensSettingsAtLaunch"
        static let didApplyLaunchAtLoginDefault = "didApplyLaunchAtLoginDefault"
    }

    // MARK: - Timing

    /// Hold threshold in milliseconds.
    var tappingTermMs: Double {
        get { defaults.object(forKey: Key.tappingTermMs) as? Double ?? Config.tappingTerm * 1000 }
        nonmutating set { defaults.set(newValue, forKey: Key.tappingTermMs) }
    }

    /// Fast-typing window in milliseconds.
    var priorIdleMs: Double {
        get { defaults.object(forKey: Key.priorIdleMs) as? Double ?? Config.priorIdle * 1000 }
        nonmutating set { defaults.set(newValue, forKey: Key.priorIdleMs) }
    }

    // MARK: - Keys

    /// The layout in use: hold modifiers, remaps and layers. Stored as JSON. Before layouts
    /// existed, the hold modifiers and Caps Lock target were saved separately; those are
    /// read once and replaced by the first save.
    var layout: Layout {
        get {
            if let data = defaults.data(forKey: Key.layout),
               let layout = try? JSONDecoder().decode(Layout.self, from: data) {
                return layout
            }
            return legacyLayout
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.layout)
            defaults.removeObject(forKey: Key.legacyKeyMap)
            defaults.removeObject(forKey: Key.legacyCapsLockTarget)
        }
    }

    /// Layouts the user saved by name, in the order they were saved. Stored as JSON.
    var savedLayouts: [SavedLayout] {
        get {
            guard let data = defaults.data(forKey: Key.savedLayouts) else { return [] }
            return (try? JSONDecoder().decode([SavedLayout].self, from: data)) ?? []
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.savedLayouts)
        }
    }

    /// Unsaved edits, kept while another layout is in use. `nil` until the first edit, and
    /// again once they're saved or discarded.
    var customLayout: Layout? {
        get { decoded(Layout.self, forKey: Key.customLayout) }
        nonmutating set { setEncoded(newValue, forKey: Key.customLayout) }
    }

    /// The layout Custom was started from, if known.
    var customBase: LayoutSelection? {
        get { decoded(LayoutSelection.self, forKey: Key.customBase) }
        nonmutating set { setEncoded(newValue, forKey: Key.customBase) }
    }

    /// The user's own Default, or `nil` for the built-in one.
    var defaultLayout: Layout? {
        get { decoded(Layout.self, forKey: Key.defaultLayout) }
        nonmutating set { setEncoded(newValue, forKey: Key.defaultLayout) }
    }

    /// Which Layout menu entry is in use, or `nil` if never saved (older versions).
    var layoutSelection: LayoutSelection? {
        get { decoded(LayoutSelection.self, forKey: Key.layoutSelection) }
        nonmutating set { setEncoded(newValue, forKey: Key.layoutSelection) }
    }

    private func decoded<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    /// Saves a value as JSON, or removes it with `nil`.
    private func setEncoded<T: Encodable>(_ value: T?, forKey key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// The layout as saved by older versions, or the default if nothing was saved.
    private var legacyLayout: Layout {
        var layout = Layout.default
        if let stored = defaults.dictionary(forKey: Key.legacyKeyMap) as? [String: String] {
            layout.homeRowMods = stored.reduce(into: [:]) { map, entry in
                if let keyCode = UInt16(entry.key), let modifier = Modifier(rawValue: entry.value) {
                    map[keyCode] = ModifierSet(modifier)
                }
            }
        }
        layout.capsLockTarget = (defaults.object(forKey: Key.legacyCapsLockTarget) as? Int)
            .flatMap { UInt16(exactly: $0) }
        return layout
    }

    // MARK: - Launch

    var opensSettingsAtLaunch: Bool {
        get { defaults.bool(forKey: Key.opensSettingsAtLaunch) }
        nonmutating set { defaults.set(newValue, forKey: Key.opensSettingsAtLaunch) }
    }

    /// Launch at login has been turned on once, on first launch.
    var didApplyLaunchAtLoginDefault: Bool {
        get { defaults.bool(forKey: Key.didApplyLaunchAtLoginDefault) }
        nonmutating set { defaults.set(newValue, forKey: Key.didApplyLaunchAtLoginDefault) }
    }
}

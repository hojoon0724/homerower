import Foundation

/// Everything a keyboard setup changes: hold modifiers and key remaps on the base layer,
/// plus the layers a held key switches to.
///
/// Saved as JSON (see `SettingsStore`), so field names are part of the saved format.
nonisolated struct Layout: Equatable, Sendable {
    /// Physical key → modifiers it holds down when held. Keys without any aren't listed.
    var homeRowMods: [UInt16: ModifierSet] = [:]
    /// Physical key → key it acts as on the base layer. Only Caps Lock is applied for now.
    var remaps: [UInt16: UInt16] = [:]
    /// Layers switched on by holding a key. Stored but not used yet.
    var layers: [Layer] = []

    /// No hold modifiers, no remaps: the keyboard as macOS has it.
    static let none = Layout()
    /// The built-in Default. The user can save their own Default over it.
    static let `default` = Layout(homeRowMods: Config.homeRowMods)

    /// The key Caps Lock acts as, or `nil` for normal Caps Lock. Caps Lock either acts as
    /// another key or has hold modifiers (`capsLockModifiers`), never both.
    var capsLockTarget: UInt16? {
        get { remaps[KeyCode.capsLock] }
        set { remaps[KeyCode.capsLock] = newValue }
    }

    /// What Caps Lock holds down when held; a tap still toggles Caps Lock.
    var capsLockModifiers: ModifierSet {
        homeRowMods[KeyCode.capsLock] ?? []
    }

    /// The key the system should turn Caps Lock into: its target, the stand-in key while
    /// it has hold modifiers, or `nil` to leave it alone.
    var capsLockSystemTarget: UInt16? {
        capsLockTarget ?? (capsLockModifiers.isEmpty ? nil : Config.capsLockStandIn)
    }
}

/// One change the user makes to a layout from the keyboard view.
nonisolated enum LayoutEdit: Equatable, Sendable {
    /// Sets the hold modifiers for a physical key; none makes it type normally.
    case modifier(ModifierSet, keyCode: UInt16)
    /// Makes Caps Lock act as another key (dropping its hold modifiers), or normal again
    /// with `nil`.
    case capsLockTarget(UInt16?)
    /// Gives Caps Lock hold modifiers (so it no longer acts as another key); a tap still
    /// toggles Caps Lock. None makes it normal again.
    case capsLockModifiers(ModifierSet)

    func applied(to layout: Layout) -> Layout {
        var layout = layout
        switch self {
        case let .modifier(modifiers, keyCode):
            layout.homeRowMods[keyCode] = modifiers.isEmpty ? nil : modifiers
        case let .capsLockTarget(target):
            layout.capsLockTarget = target
            if target != nil { layout.homeRowMods[KeyCode.capsLock] = nil }
        case let .capsLockModifiers(modifiers):
            layout.homeRowMods[KeyCode.capsLock] = modifiers.isEmpty ? nil : modifiers
            if !modifiers.isEmpty { layout.capsLockTarget = nil }
        }
        return layout
    }
}

/// Where Save Layout… puts a layout.
nonisolated enum LayoutSaveTarget: Hashable, Sendable {
    case newLayout(name: String)
    /// Replaces the built-in Default with the user's own.
    case `default`
    case saved(SavedLayout.ID)
}

/// A set of remaps that takes over the keyboard while its activation key is held.
nonisolated struct Layer: Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// The key that switches to this layer while held.
    var activationKey: UInt16
    /// Physical key → key it acts as while the layer is on.
    var remaps: [UInt16: UInt16] = [:]
}

/// Which entry of the Layout menu is in use. Saved, so it's part of the saved format.
nonisolated enum LayoutSelection: Hashable, Sendable, Codable {
    case preset(LayoutPreset)
    case saved(SavedLayout.ID)
    /// The assembly area for unsaved edits (see `EventTap.customLayout`).
    case custom
}

/// The layouts built into the app, offered above the user's saved ones.
nonisolated enum LayoutPreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case none
    case `default`

    var id: Self { self }

    var displayName: String {
        switch self {
        case .none: "None"
        case .default: "Default"
        }
    }

    /// Names a new saved layout can't take.
    static let reservedNames = ["None", "Default", "Custom"]
}

// MARK: - Coding

// Key codes are written as string keys so the JSON stays a readable object. Entries that
// no longer decode (unknown modifier, bad key code) are dropped rather than failing the
// whole layout, and missing fields fall back to empty.

nonisolated extension Layout: Codable {
    private enum CodingKeys: String, CodingKey {
        case homeRowMods, remaps, layers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Each key lists its modifiers by name. Before combinations, it was a single name.
        let mods: [String: [String]]
        if let lists = try? container.decodeIfPresent([String: [String]].self, forKey: .homeRowMods) {
            mods = lists
        } else {
            mods = try container.decodeIfPresent([String: String].self, forKey: .homeRowMods)?.mapValues { [$0] } ?? [:]
        }
        homeRowMods = mods.reduce(into: [:]) { map, entry in
            let modifiers = ModifierSet(entry.value.compactMap(Modifier.init(rawValue:)))
            if let keyCode = UInt16(entry.key), !modifiers.isEmpty {
                map[keyCode] = modifiers
            }
        }
        remaps = try container.decodeIfPresent([String: Int].self, forKey: .remaps).map(Self.decodeRemaps) ?? [:]
        layers = try container.decodeIfPresent([Layer].self, forKey: .layers) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            Dictionary(uniqueKeysWithValues: homeRowMods.map { (String($0.key), $0.value.modifiers.map(\.rawValue)) }),
            forKey: .homeRowMods
        )
        try container.encode(Self.encodeRemaps(remaps), forKey: .remaps)
        try container.encode(layers, forKey: .layers)
    }

    fileprivate static func encodeRemaps(_ remaps: [UInt16: UInt16]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: remaps.map { (String($0.key), Int($0.value)) })
    }

    fileprivate static func decodeRemaps(_ stored: [String: Int]) -> [UInt16: UInt16] {
        stored.reduce(into: [:]) { map, entry in
            if let from = UInt16(entry.key), let to = UInt16(exactly: entry.value) {
                map[from] = to
            }
        }
    }
}

nonisolated extension Layer: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, activationKey, remaps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        activationKey = try container.decode(UInt16.self, forKey: .activationKey)
        remaps = try container.decodeIfPresent([String: Int].self, forKey: .remaps).map(Layout.decodeRemaps) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(activationKey, forKey: .activationKey)
        try container.encode(Layout.encodeRemaps(remaps), forKey: .remaps)
    }
}

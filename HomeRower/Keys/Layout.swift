import Foundation

/// Everything a keyboard setup changes: hold modifiers and key remaps on the base layer,
/// plus the layers a held key switches to.
///
/// Saved as JSON (see `SettingsStore`), so field names are part of the saved format.
nonisolated struct Layout: Equatable, Sendable {
    /// Physical key → modifiers it holds down when held. Keys without any aren't listed.
    var homeRowMods: [UInt16: ModifierSet] = [:]
    /// Physical key → key (and Shift) it acts as on the base layer. A remapped key has no
    /// hold action: it's one or the other.
    var remaps: [UInt16: KeyStroke] = [:]
    /// Layers 1 and up, in order; the base layer above is Layer 0. A layer's number is
    /// its place here, so deleting one renumbers the ones after it. Each is switched on by
    /// holding a key (not used yet).
    var layers: [Layer] = []

    /// The most layers a layout can have, counting Layer 0.
    static let maxLayerCount = 8

    /// Whether another layer can be added.
    var canAddLayer: Bool { layers.count + 1 < Self.maxLayerCount }

    /// No hold modifiers, no remaps: the keyboard as macOS has it.
    static let none = Layout()
    /// The built-in Default. The user can save their own Default over it.
    static let `default` = Layout(homeRowMods: Config.homeRowMods)

    /// The key Caps Lock acts as, or `nil` for normal Caps Lock. Caps Lock either acts as
    /// another key or has hold modifiers (`capsLockModifiers`), never both.
    var capsLockTarget: UInt16? {
        get { remaps[KeyCode.capsLock]?.keyCode }
        set { remaps[KeyCode.capsLock] = newValue.map { KeyStroke($0) } }
    }

    /// What Caps Lock holds down when held; a tap still toggles Caps Lock.
    var capsLockModifiers: ModifierSet {
        homeRowMods[KeyCode.capsLock] ?? []
    }

    /// The key a physical key acts as while a layer is on (`nil` for Layer 0): its remap on
    /// that layer, or else what it does on Layer 0. So Caps Lock remapped to Esc on Layer 0
    /// is Esc on every layer that doesn't give it a key of its own.
    func key(for keyCode: UInt16, inLayer layerID: Layer.ID?) -> KeyStroke {
        if let layerID, let target = layers.first(where: { $0.id == layerID })?.remaps[keyCode] {
            return target
        }
        return remaps[keyCode] ?? KeyStroke(keyCode)
    }

    /// The key the system should turn Caps Lock into: the stand-in key while it has hold
    /// modifiers or a layer remaps it (so HomeRower can tell it from the key it acts as),
    /// otherwise its target, or `nil` to leave it alone.
    var capsLockSystemTarget: UInt16? {
        if !capsLockModifiers.isEmpty || layers.contains(where: { $0.remaps[KeyCode.capsLock] != nil }) {
            return Config.capsLockStandIn
        }
        return capsLockTarget
    }

    /// The number of the layer a key switches to while held (1 and up), if it's a layer key.
    func layerNumber(activatedBy keyCode: UInt16) -> Int? {
        layers.firstIndex { $0.activationKeys.contains(keyCode) }.map { $0 + 1 }
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
    /// Makes a key on the base layer act as another key (dropping what holding it does),
    /// or type normally again with `nil`. Caps Lock goes through `capsLockTarget`.
    case remap(KeyStroke?, keyCode: UInt16)
    /// Adds a layer after the others, unless the layout already has the most it can.
    case addLayer(Layer)
    /// Deletes a layer; the layers after it move up a number.
    case deleteLayer(Layer.ID)
    /// Makes a key act as another key while a layer is on, or pass through with `nil`. A
    /// layer's own activation keys can't be remapped there: one is held down the whole
    /// time, and the others just type.
    case layerRemap(KeyStroke?, keyCode: UInt16, layerID: Layer.ID)
    /// Makes holding a key switch to a layer (dropping its hold modifiers), or stop with
    /// `nil`. A layer can have several such keys, but a key switches to one layer.
    case layerKey(Layer.ID?, keyCode: UInt16)

    func applied(to layout: Layout) -> Layout {
        var layout = layout
        switch self {
        case let .modifier(modifiers, keyCode):
            layout.homeRowMods[keyCode] = modifiers.isEmpty ? nil : modifiers
            if !modifiers.isEmpty {
                layout.clearLayerKey(keyCode)
                layout.remaps[keyCode] = nil
            }
        case let .capsLockTarget(target):
            layout.capsLockTarget = target
            if target != nil { layout.homeRowMods[KeyCode.capsLock] = nil }
        case let .capsLockModifiers(modifiers):
            layout.homeRowMods[KeyCode.capsLock] = modifiers.isEmpty ? nil : modifiers
            if !modifiers.isEmpty { layout.capsLockTarget = nil }
        case let .remap(target, keyCode):
            let target = target == KeyStroke(keyCode) ? nil : target
            layout.remaps[keyCode] = target
            if target != nil {
                layout.homeRowMods[keyCode] = nil
                layout.clearLayerKey(keyCode)
            }
        case let .addLayer(layer):
            if layout.canAddLayer { layout.layers.append(layer) }
        case let .deleteLayer(layerID):
            layout.layers.removeAll { $0.id == layerID }
        case let .layerRemap(target, keyCode, layerID):
            guard let index = layout.layers.firstIndex(where: { $0.id == layerID }),
                  !layout.layers[index].activationKeys.contains(keyCode) else { break }
            layout.layers[index].remaps[keyCode] = target == KeyStroke(keyCode) ? nil : target
        case let .layerKey(layerID, keyCode):
            layout.clearLayerKey(keyCode)
            guard let layerID, let index = layout.layers.firstIndex(where: { $0.id == layerID }) else { break }
            layout.layers[index].activationKeys.insert(keyCode)
            layout.layers[index].remaps[keyCode] = nil
            layout.homeRowMods[keyCode] = nil
            layout.remaps[keyCode] = nil
        }
        return layout
    }
}

private extension Layout {
    /// Stops a key switching to any layer.
    mutating func clearLayerKey(_ keyCode: UInt16) {
        for index in layers.indices {
            layers[index].activationKeys.remove(keyCode)
        }
    }
}

/// Where Save Layout… puts a layout.
nonisolated enum LayoutSaveTarget: Hashable, Sendable {
    case newLayout(name: String)
    /// Replaces the built-in Default with the user's own.
    case `default`
    case saved(SavedLayout.ID)
}

/// A set of remaps that takes over the keyboard while its activation key is held. Keys
/// it doesn't remap pass through and type as they do on the base layer.
nonisolated struct Layer: Identifiable, Equatable, Sendable {
    var id = UUID()
    /// The keys that switch to this layer while held; none until one is chosen.
    var activationKeys: Set<UInt16> = []
    /// Physical key → key (and Shift) it acts as while the layer is on.
    var remaps: [UInt16: KeyStroke] = [:]

    /// The arrow keys: ←, →, ↓, ↑.
    static let arrowKeys: Set<UInt16> = [123, 124, 125, 126]

    /// Keys that send key presses: not modifier keys or fn, which only change flags. Caps
    /// Lock counts, since HomeRower turns it into a key press when it needs to.
    private static func sendsKeyPresses(_ keyCode: UInt16) -> Bool {
        keyCode != KeyCode.function
            && !Modifier.allCases.contains { $0.keyCode == keyCode }
    }

    /// Keys a layer can remap: ones that send key presses, apart from the arrows, which
    /// keep their place on every layer.
    static func canRemap(_ keyCode: UInt16) -> Bool {
        sendsKeyPresses(keyCode) && !arrowKeys.contains(keyCode)
    }

    /// Keys that can switch to a layer while held: any a layer can remap, apart from Caps
    /// Lock for now.
    static func canBeLayerKey(_ keyCode: UInt16) -> Bool {
        keyCode != KeyCode.capsLock && canRemap(keyCode)
    }

    /// Keys a layer can make another key act as: ones that send key presses (arrows too),
    /// apart from Caps Lock, which only toggles.
    static func canActAs(_ keyCode: UInt16) -> Bool {
        keyCode != KeyCode.capsLock && sendsKeyPresses(keyCode)
    }
}

/// A key to send, with or without Shift: e.g. [ or, shifted, {. Shift goes on that key
/// alone, so it never spills onto keys typed around it.
nonisolated struct KeyStroke: Hashable, Sendable {
    var keyCode: UInt16
    var isShifted = false

    init(_ keyCode: UInt16, isShifted: Bool = false) {
        self.keyCode = keyCode
        self.isShifted = isShifted
    }
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
        /// Remaps that send Shift too, kept apart so older versions still read the rest.
        case shiftedRemaps
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
        remaps = Self.decodeStrokes(
            plain: try container.decodeIfPresent([String: Int].self, forKey: .remaps),
            shifted: try container.decodeIfPresent([String: Int].self, forKey: .shiftedRemaps)
        )
        // Keys that can't be remapped (any more), like the arrows.
        .filter { Layer.canRemap($0.key) }
        let layers = try container.decodeIfPresent([Layer].self, forKey: .layers) ?? []
        self.layers = Array(layers.prefix(Self.maxLayerCount - 1))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            Dictionary(uniqueKeysWithValues: homeRowMods.map { (String($0.key), $0.value.modifiers.map(\.rawValue)) }),
            forKey: .homeRowMods
        )
        try container.encode(Self.encodeRemaps(remaps.filter { !$0.value.isShifted }.mapValues(\.keyCode)), forKey: .remaps)
        let shifted = remaps.filter(\.value.isShifted).mapValues(\.keyCode)
        if !shifted.isEmpty {
            try container.encode(Self.encodeRemaps(shifted), forKey: .shiftedRemaps)
        }
        try container.encode(layers, forKey: .layers)
    }

    /// Remaps saved in two parts, plain and with Shift, as one map.
    fileprivate static func decodeStrokes(plain: [String: Int]?, shifted: [String: Int]?) -> [UInt16: KeyStroke] {
        let plain = plain.map(decodeRemaps) ?? [:]
        let shifted = shifted.map(decodeRemaps) ?? [:]
        return plain.mapValues { KeyStroke($0) }
            .merging(shifted.mapValues { KeyStroke($0, isShifted: true) }) { _, shifted in shifted }
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
        case id, activationKeys, remaps
        /// Remaps that send Shift too, kept apart so older versions still read the rest.
        case shiftedRemaps
        /// Before layers could have several keys, the one key.
        case activationKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        if let keys = try container.decodeIfPresent([UInt16].self, forKey: .activationKeys) {
            activationKeys = Set(keys)
        } else {
            activationKeys = Set([try container.decodeIfPresent(UInt16.self, forKey: .activationKey)].compactMap { $0 })
        }
        remaps = Layout.decodeStrokes(
            plain: try container.decodeIfPresent([String: Int].self, forKey: .remaps),
            shifted: try container.decodeIfPresent([String: Int].self, forKey: .shiftedRemaps)
        )
            // Keys that can't be remapped (any more), like the arrows.
            .filter { Layer.canRemap($0.key) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(activationKeys.sorted(), forKey: .activationKeys)
        try container.encode(Layout.encodeRemaps(remaps.filter { !$0.value.isShifted }.mapValues(\.keyCode)), forKey: .remaps)
        let shifted = remaps.filter(\.value.isShifted).mapValues(\.keyCode)
        if !shifted.isEmpty {
            try container.encode(Layout.encodeRemaps(shifted), forKey: .shiftedRemaps)
        }
    }
}

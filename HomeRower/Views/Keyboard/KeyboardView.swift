import Carbon
import SwiftUI

/// A MacBook-style keyboard with a bar of its layers above. On Layer 0, click a letter key
/// to choose the modifier it produces when held; on another layer, click a key to choose
/// the key it acts as while that layer is on.
struct KeyboardView: View {
    @Bindable var eventTap: EventTap
    /// The layer being shown and edited; `nil` for Layer 0.
    @State private var selectedLayerID: Layer.ID?
    /// The added layer under the pointer, which shows its × to delete it.
    @State private var hoveredLayerID: Layer.ID?
    /// Physical key → what it types with the current input source.
    @State private var labels: [UInt16: String] = [:]
    @State private var selectedKey: UInt16?
    /// Raw key state, to show where a remapped Caps Lock physically is.
    @State private var physicalKeys = PhysicalKeyMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            layerBar

            GeometryReader { geometry in
                let unit = geometry.size.width / KeySpec.rowWidth
                VStack(spacing: 0) {
                    ForEach(KeySpec.rows) { row in
                        HStack(spacing: 0) {
                            ForEach(row.slots) { slot in
                                // Half-height keys stack (↑ over ↓) or sit at the bottom (← →).
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    ForEach(slot.keys) { key in
                                        keyButton(key, unit: unit)
                                            .frame(height: key.isHalfHeight ? unit / 2 : unit)
                                    }
                                }
                                .frame(width: slot.width * unit, height: unit)
                            }
                        }
                    }
                }
            }
            .aspectRatio(KeySpec.rowWidth / CGFloat(KeySpec.rows.count), contentMode: .fit)

            Text(selectedLayer == nil
                ? "Click a key to remap it to another key, or to choose what holding it does: hold modifiers (letter keys and Caps Lock) or switch to a layer. Keys show what they type with your current input source; hold modifiers stay on the same physical keys when you switch layouts."
                : "Click a key to choose the key it acts as on this layer. Keys you haven’t remapped pass through and type as they do on Layer 0.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Only watch raw keys while the keyboard is on screen.
        .onAppear { physicalKeys.start() }
        .onDisappear { physicalKeys.stop() }
        .task {
            // Relabel the keys whenever the input source changes (e.g. ABC ↔ Dvorak).
            // The key map itself is by physical position, so it doesn't change.
            loadLabels()
            let changes = DistributedNotificationCenter.default().notifications(
                named: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
            )
            for await _ in changes {
                loadLabels()
            }
        }
    }

    /// The layer being shown, or `nil` for Layer 0. A layer that's gone (e.g. after
    /// switching layouts) falls back to Layer 0.
    private var selectedLayer: Layer? {
        eventTap.layout.layers.first { $0.id == selectedLayerID }
    }

    /// Layer 0, then each added layer, with + on the right to add another until the layout
    /// has as many as it can. The bar has a slot for every layer a layout can have, all the
    /// same width, so a full set spans the keyboard exactly; + sits over the last slot,
    /// which is only free while there's room for another layer.
    private var layerBar: some View {
        let layers = eventTap.layout.layers
        let emptySlots = Layout.maxLayerCount - 1 - layers.count
        return HStack(spacing: 6) {
            layerChip(0, id: nil)
            ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                layerChip(index + 1, id: layer.id)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            // Free slots keep every chip the same width.
            ForEach(0..<max(0, emptySlots), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity)
            }
        }
        // + floats over the last free slot rather than being one, so it keeps its identity
        // as slots come and go and only scales (about its own center) when it appears or
        // goes away at the limit.
        .overlay(alignment: .trailing) {
            if eventTap.layout.canAddLayer {
                Button("Add Layer", systemImage: "plus") {
                    if let id = eventTap.addLayer() { selectedLayerID = id }
                }
                .labelStyle(.iconOnly)
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(.green)
                .help("Add Layer")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(height: 24)
        // Animates every change to the layers, whichever way it happens (+, ×, the
        // replace alert, or switching layouts); later layers slide into a deleted one's place.
        .animation(.snappy(duration: 0.25), value: layers.map(\.id))
        .animation(.snappy(duration: 0.25), value: selectedLayer?.id)
    }

    /// Shows a layer: the layers symbol and its number, highlighted while it's shown.
    /// Added layers show an × on the right to delete them while hovered. `id` is `nil` for Layer 0,
    /// which can't be deleted.
    private func layerChip(_ number: Int, id: Layer.ID?) -> some View {
        // Buttons rather than a segmented picker: segments can't show a symbol and text
        // together, or hold a delete button.
        let isSelected = selectedLayer?.id == id
        let isHovered = id != nil && hoveredLayerID == id
        let shape = RoundedRectangle(cornerRadius: 7)
        return Button {
            selectedLayerID = id
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "square.2.layers.3d.top.filled")
                Text("\(number)")
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Layer \(number)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .trailing) {
            if let id {
                Button("Delete Layer \(number)", systemImage: "xmark") {
                    delete(id)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                // Shown only while hovered, so the numbers line up evenly otherwise.
                .opacity(isHovered ? 0.75 : 0)
                .allowsHitTesting(isHovered)
                .help("Delete Layer \(number)")
            }
        }
        .onHover { inside in
            guard let id else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                if inside {
                    hoveredLayerID = id
                } else if hoveredLayerID == id {
                    hoveredLayerID = nil
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: shape)
    }

    /// Deletes a layer. If it was shown, the layer before it is shown instead.
    private func delete(_ id: Layer.ID) {
        let layers = eventTap.layout.layers
        if selectedLayer?.id == id, let index = layers.firstIndex(where: { $0.id == id }) {
            selectedLayerID = index > 0 ? layers[index - 1].id : nil
        }
        eventTap.deleteLayer(id: id)
    }

    @ViewBuilder
    private func keyButton(_ key: KeySpec, unit: CGFloat) -> some View {
        if let layer = selectedLayer {
            layerKeyButton(key, layer: layer, unit: unit)
        } else {
            baseKeyButton(key, unit: unit)
        }
    }

    /// A key on Layer 0: shows the key it acts as if remapped, otherwise its own label with
    /// what holding it does (modifiers or a layer).
    private func baseKeyButton(_ key: KeySpec, unit: CGFloat) -> some View {
        let isCapsLock = key.keyCode == KeyCode.capsLock
        let ownLabel = key.legend ?? labels[key.keyCode] ?? ""
        let target = isCapsLock ? eventTap.capsLockTarget.map { KeyStroke($0) } : eventTap.layout.remaps[key.keyCode]
        let modifiers = isCapsLock ? eventTap.layout.capsLockModifiers : eventTap.keyMap[key.keyCode] ?? []
        let layer = eventTap.layout.layerNumber(activatedBy: key.keyCode)
        let isMappable = Layer.canRemap(key.keyCode)
        let name = isCapsLock ? "Caps Lock" : (ownLabel.isEmpty ? KeyNames.name(for: key.keyCode) : ownLabel)

        return Button {
            selectedKey = key.keyCode
        } label: {
            KeyCap(
                label: target.map { KeySpec.displayName(for: $0) } ?? ownLabel,
                modifiers: modifiers,
                hand: isCapsLock ? .left : Config.hand(of: key.keyCode),
                isRemapped: target != nil,
                layer: layer,
                isMappable: isMappable,
                pressState: pressState(for: key.keyCode),
                unit: unit
            )
        }
        .buttonStyle(.plain)
        .disabled(!isMappable)
        .accessibilityLabel(name)
        .accessibilityValue(baseKeyDescription(target: target, modifiers: modifiers, layer: layer, isCapsLock: isCapsLock))
        .popover(isPresented: isPopoverPresented(for: key), arrowEdge: .bottom) {
            KeyAssignView(
                eventTap: eventTap,
                keyCode: key.keyCode,
                keyLabel: isCapsLock ? "Caps Lock" : (ownLabel.isEmpty ? KeySpec.displayName(for: key.keyCode) : ownLabel)
            )
        }
    }

    private func baseKeyDescription(target: KeyStroke?, modifiers: ModifierSet, layer: Int?, isCapsLock: Bool) -> String {
        if let target { return "Acts as \(KeyNames.name(for: target))" }
        if let layer { return "Hold for Layer \(layer)" }
        if modifiers.isEmpty { return isCapsLock ? "Normal Caps Lock" : "Types normally" }
        let held = "Hold for \(modifiers.modifiers.map(\.displayName).formatted(.list(type: .and)))"
        return isCapsLock ? held + ", tap for Caps Lock" : held
    }

    /// A key on an added layer: shows the key it acts as there, or its base label while it
    /// passes through.
    /// Highlighted only when remapped on this layer; a key passing through shows what it
    /// does on Layer 0 (e.g. Esc for a Caps Lock remapped to Esc there).
    private func layerKeyButton(_ key: KeySpec, layer: Layer, unit: CGFloat) -> some View {
        let isCapsLock = key.keyCode == KeyCode.capsLock
        let keyLabel = isCapsLock ? "Caps Lock" : (key.legend ?? labels[key.keyCode] ?? "")
        let baseStroke = eventTap.layout.key(for: key.keyCode, inLayer: nil)
        let baseKey = baseStroke.keyCode
        let baseLabel = baseStroke == KeyStroke(key.keyCode)
            ? (key.legend ?? labels[key.keyCode] ?? "")
            : KeySpec.displayName(for: baseStroke)
        let target = layer.remaps[key.keyCode]
        // The key that switches to this layer is held down the whole time it's on, so it
        // can't do anything else here.
        let isThisLayersKey = layer.activationKeys.contains(key.keyCode)
        let isMappable = Layer.canRemap(key.keyCode) && !isThisLayersKey
        // This layer's keys show its badge. Other layer keys just type once a layer is on.
        let layerKey = isThisLayersKey ? eventTap.layout.layerNumber(activatedBy: key.keyCode) : nil

        return Button {
            selectedKey = key.keyCode
        } label: {
            KeyCap(
                label: target.map { KeySpec.displayName(for: $0) } ?? baseLabel,
                isRemapped: target != nil,
                layer: layerKey,
                isMappable: isMappable,
                pressState: pressState(for: key.keyCode),
                unit: unit
            )
        }
        .buttonStyle(.plain)
        .disabled(!isMappable)
        .accessibilityLabel(keyLabel.isEmpty ? KeyNames.name(for: key.keyCode) : keyLabel)
        .accessibilityValue(isThisLayersKey ? "Held to switch to this layer" : target.map { "Acts as \(KeyNames.name(for: $0))" }
            ?? (baseKey == key.keyCode ? "Passes through" : "Passes through, acts as \(KeyNames.name(for: baseKey))"))
        .popover(isPresented: isPopoverPresented(for: key), arrowEdge: .bottom) {
            LayerKeyRemapView(
                eventTap: eventTap,
                layerID: layer.id,
                keyCode: key.keyCode,
                keyLabel: keyLabel.isEmpty ? KeySpec.displayName(for: key.keyCode) : keyLabel,
                baseLabel: baseLabel.isEmpty ? KeySpec.displayName(for: baseKey) : baseLabel
            )
        }
    }

    /// Whether the physical key is up, pressed, or held as its hold modifier.
    private func pressState(for keyCode: UInt16) -> KeyCap.PressState {
        // A remapped Caps Lock reaches the event tap as its target key, so the raw key
        // state decides which of the two was really pressed.
        if let target = eventTap.capsLockTarget, physicalKeys.isWatching,
           keyCode == KeyCode.capsLock || keyCode == target {
            let isCapsLock = keyCode == KeyCode.capsLock
            let isDown = physicalKeys.isDown(keyCode)
            // A hold on the target key belongs to whichever of the two is physically down.
            let holdIsCapsLock = physicalKeys.isDown(KeyCode.capsLock) && !physicalKeys.isDown(target)
            let isHeld = isDown && eventTap.heldKeys.contains(target) && holdIsCapsLock == isCapsLock
            return Self.pressState(isDown: isDown, isHeld: isHeld)
        }
        return Self.pressState(isDown: eventTap.pressedKeys.contains(keyCode), isHeld: eventTap.heldKeys.contains(keyCode))
    }

    private static func pressState(isDown: Bool, isHeld: Bool) -> KeyCap.PressState {
        if isHeld { return .held }
        if isDown { return .pressed }
        return .up
    }

    /// Shows a key's popover while it's the selected key; closing the popover deselects it.
    private func isPopoverPresented(for key: KeySpec) -> Binding<Bool> {
        Binding(
            get: { selectedKey == key.keyCode },
            set: { if !$0 { selectedKey = nil } }
        )
    }

    private func loadLabels() {
        var result: [UInt16: String] = [:]
        for row in KeySpec.rows {
            for key in row.keys where key.legend == nil {
                result[key.keyCode] = KeyLabels.character(for: key.keyCode)?.uppercased()
            }
        }
        labels = result
    }
}

#Preview("Keyboard") {
    KeyboardView(eventTap: .preview())
        .padding()
        .frame(width: 600)
}

#Preview("Caps Lock Remapped") {
    KeyboardView(eventTap: .preview(capsLockTarget: KeyCode.escape))
        .padding()
        .frame(width: 600)
}

#Preview("Layers") {
    let eventTap = EventTap.preview()
    // Preview settings persist between runs, so start from no layers.
    for layer in eventTap.layout.layers { eventTap.deleteLayer(id: layer.id) }
    for _ in 0..<3 { eventTap.addLayer() }
    return KeyboardView(eventTap: eventTap)
        .padding()
        .frame(width: 600)
}

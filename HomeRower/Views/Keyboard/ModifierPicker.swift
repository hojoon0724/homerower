import SwiftUI

/// Chooses the modifiers a key holds down when held. Any combination can be checked.
/// The key's own side comes first; the other side's modifiers are tucked away below.
struct ModifierPicker: View {
    let keyLabel: String
    /// The hand the key is on; `nil` shows every modifier together.
    let hand: Hand?
    @Binding var selection: ModifierSet
    /// What the key does with nothing checked; defaults to "<key> always types."
    var nothingChecked: String?
    /// Pads itself and fixes its width, as a popover's whole content; off inside a view
    /// that does that already.
    var isPadded = true
    @State private var showsOtherSide: Bool

    init(
        keyLabel: String,
        hand: Hand?,
        selection: Binding<ModifierSet>,
        nothingChecked: String? = nil,
        isPadded: Bool = true
    ) {
        self.keyLabel = keyLabel
        self.hand = hand
        _selection = selection
        self.nothingChecked = nothingChecked
        self.isPadded = isPadded
        // Hidden by default, but not when it holds something already checked.
        let otherSide = Self.modifiers(onLeft: hand != .left)
        _showsOtherSide = State(initialValue: otherSide.contains { selection.wrappedValue.contains($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When \(keyLabel) is held")
                .font(.headline)
            if let hand {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Self.modifiers(onLeft: hand == .left), id: \.self) { modifier in
                        checkbox(modifier, title: modifier.kindName)
                    }
                }
                Button {
                    showsOtherSide.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showsOtherSide ? "chevron.down" : "chevron.right")
                        Text(hand == .left ? "Right-Side Modifiers" : "Left-Side Modifiers")
                        Spacer()
                    }
                    .opacity(0.5)
                    .font(.callout)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsOtherSide {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Self.modifiers(onLeft: hand != .left), id: \.self) { modifier in
                            checkbox(modifier, title: modifier.displayName)
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Modifier.displayOrder, id: \.self) { modifier in
                        checkbox(modifier, title: modifier.displayName)
                    }
                }
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(isPadded ? 16 : 0)
        .frame(width: isPadded ? 200 : nil, alignment: .leading)
    }

    private func checkbox(_ modifier: Modifier, title: String) -> some View {
        Toggle(isOn: Binding(
            get: { selection.contains(modifier) },
            set: { isOn in
                var modifiers = selection
                if isOn { modifiers.insert(ModifierSet(modifier)) } else { modifiers.remove(ModifierSet(modifier)) }
                selection = modifiers
            }
        )) {
            Text("\(modifier.symbol)  \(title)")
        }
        .toggleStyle(.checkbox)
    }

    private var summary: String {
        selection.isEmpty
            ? "Nothing checked: \(nothingChecked ?? "\(keyLabel) always types.")"
            : "Holds \(selection.modifiers.map(\.symbol).joined())."
    }

    /// One side's modifiers, in macOS order (⌃ ⌥ ⇧ ⌘).
    private static func modifiers(onLeft: Bool) -> [Modifier] {
        Modifier.displayOrder.filter { $0.isLeft == onLeft }
    }
}

#Preview("Combination Chosen") {
    @Previewable @State var selection: ModifierSet = [.leftShift, .leftCommand]
    ModifierPicker(keyLabel: "A", hand: .left, selection: $selection)
}

#Preview("Other Side Chosen") {
    @Previewable @State var selection: ModifierSet = [.leftCommand, .rightOption]
    ModifierPicker(keyLabel: "F", hand: .left, selection: $selection)
}

#Preview("Nothing Chosen") {
    @Previewable @State var selection: ModifierSet = []
    ModifierPicker(keyLabel: "J", hand: .right, selection: $selection)
}

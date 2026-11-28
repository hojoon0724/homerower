import SwiftUI

/// One key on the drawn keyboard: its label and the modifiers it holds, if any.
struct KeyCap: View {
    /// What the physical key is doing right now.
    enum PressState {
        case up
        case pressed
        /// Held long enough to act as its hold modifier.
        case held
    }

    let label: String
    /// What the key holds down when held, shown side by side (⌃ ⌥ ⇧ ⌘).
    var modifiers: ModifierSet = []
    /// The hand the key is on. Modifiers from the other side are labeled "Left"/"Right".
    var hand: Hand?
    /// The key acts as another key (e.g. Caps Lock → Esc); `label` is that key.
    var isRemapped = false
    /// The layer holding the key switches to, shown where modifiers would be.
    var layer: Int?
    let isMappable: Bool
    var pressState = PressState.up
    let unit: CGFloat

    private var isHighlighted: Bool { !modifiers.isEmpty || isRemapped || layer != nil }

    /// Outline and tint while the key is down: blue when pressed, red once it's a hold.
    private var pressColor: Color? {
        switch pressState {
        case .up: nil
        case .pressed: .blue
        case .held: .red
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.1)
        // The letter is centered in the space above the modifier line, which sits
        // close to the bottom edge of the key.
        VStack(spacing: -7) {
            Spacer(minLength: 0)
            Text(label)
                .font(.system(size: unit * 0.3, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, unit * 0.08)
                .foregroundStyle(isRemapped ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(isMappable ? .primary : .tertiary))
            Spacer(minLength: 0)
            if let layer {
                HStack(spacing: unit * 0.04) {
                    Image(systemName: "square.2.layers.3d.top.filled")
                    Text("\(layer)")
                }
                .font(.system(size: unit * 0.24, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, unit * 0.06)
            } else if !modifiers.isEmpty {
                // Symbols on one line that never wraps; it shrinks to fit instead. A side
                // label sits on the side it names: "LEFT ⇧" and "⇧ RIGHT".
                HStack(alignment: .center, spacing: unit * 0.02) {
                    ForEach(modifiers.modifiers, id: \.self) { modifier in
                        HStack(alignment: .center, spacing: 0) {
                            let showsSide = isFromOtherSide(modifier)
                            if showsSide && modifier.isLeft { sideLabel(modifier) }
                            Text(modifier.symbol)
                                .font(.system(size: unit * 0.3, weight: .semibold))
                            if showsSide && !modifier.isLeft { sideLabel(modifier) }
                        }
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, unit * 0.02)
            }
        }
        .foregroundStyle(isMappable ? .primary : .tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(isHighlighted ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor))
            if let pressColor {
                shape.fill(pressColor.opacity(0.15))
            }
        }
        .overlay {
            if let pressColor {
                shape.strokeBorder(pressColor, lineWidth: 2)
            } else {
                shape.strokeBorder(isHighlighted ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
            }
        }
        .contentShape(shape)
        .scaleEffect(pressState == .up ? 1 : 0.9)
        .animation(.easeOut(duration: 0.08), value: pressState)
        .padding(unit * 0.05)
    }

    /// Modifiers on the key's own side go without saying; ones from the other side (or
    /// on a key with no side) are labeled.
    private func isFromOtherSide(_ modifier: Modifier) -> Bool {
        guard let hand else { return true }
        return modifier.isLeft != (hand == .left)
    }

    private func sideLabel(_ modifier: Modifier) -> some View {
        Text(modifier.side)
            .font(.system(size: max(5, unit * 0.1), weight: .black))
            .textCase(.uppercase)
            .tracking(-0.2)
    }
}

#Preview("Key Caps") {
    // A few caps at a fixed size, for tuning the key cap layout.
    let unit: CGFloat = 48
    HStack(spacing: 0) {
        KeyCap(label: "A", modifiers: .leftShift, hand: .left, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "U", modifiers: .leftCommand, hand: .left, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "G", isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "H", modifiers: .rightCommand, hand: .right, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "S", modifiers: .rightShift, hand: .right, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "Esc", isRemapped: true, isMappable: true, unit: unit)
            .frame(width: unit * 1.75, height: unit)
        KeyCap(label: "Left ⌃", isRemapped: true, isMappable: true, unit: unit)
            .frame(width: unit * 1.75, height: unit)
        KeyCap(label: "-", layer: 1, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "⇥", isMappable: false, unit: unit)
            .frame(width: unit * 1.5, height: unit)
    }
    .padding()
}

#Preview("Combinations and Other Side") {
    let unit: CGFloat = 48
    HStack(spacing: 0) {
        KeyCap(label: "A", modifiers: [.leftShift, .leftCommand], hand: .left, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "S", modifiers: [.leftControl, .leftOption, .leftCommand], hand: .left, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "D", modifiers: .rightOption, hand: .left, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "F", modifiers: [.leftCommand, .rightShift], hand: .left, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "J", modifiers: .rightCommand, hand: .right, isMappable: true, unit: unit)
            .frame(width: unit, height: unit)
    }
    .padding()
}

#Preview("Pressed and Held") {
    let unit: CGFloat = 48
    HStack(spacing: 0) {
        KeyCap(label: "A", modifiers: .leftShift, hand: .left, isMappable: true, pressState: .pressed, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "U", modifiers: .leftCommand, hand: .left, isMappable: true, pressState: .held, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "G", isMappable: true, pressState: .pressed, unit: unit)
            .frame(width: unit, height: unit)
        KeyCap(label: "⇧", isMappable: false, pressState: .pressed, unit: unit)
            .frame(width: unit * 2.25, height: unit)
        KeyCap(label: "", isMappable: false, unit: unit)
            .frame(width: unit * 3, height: unit)
    }
    .padding()
}

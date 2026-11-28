import SwiftUI

/// Changes what a key does while a layer is on: act as another key (recorded from the
/// next key press), or pass through and type as it does on the base layer.
struct LayerKeyRemapView: View {
    let eventTap: EventTap
    let layerID: Layer.ID
    let keyCode: UInt16
    /// The physical key, as its key cap shows it on Layer 0 (or "Caps Lock").
    let keyLabel: String
    /// What the key does on Layer 0, which it keeps while it passes through: usually
    /// `keyLabel`, but e.g. Esc for a Caps Lock remapped to Esc.
    let baseLabel: String
    /// Starts out recording, so the next key pressed is the one this key acts as.
    @State private var isRecording = true
    @State private var errorMessage: String?

    private var layerIndex: Int? {
        eventTap.layout.layers.firstIndex { $0.id == layerID }
    }

    private var target: KeyStroke? {
        layerIndex.flatMap { eventTap.layout.layers[$0].remaps[keyCode] }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Once remapped, the key goes by what it now types: "& on Layer 1".
            Text("\(target.map { KeySpec.displayName(for: $0) } ?? keyLabel) on \(layerIndex.map { "Layer \($0 + 1)" } ?? "this layer")")
                .font(.headline)
                .lineLimit(1)

            KeyRecordField(
                eventTap: eventTap,
                key: target,
                accessibilityLabel: "\(keyLabel) acts as",
                accessibilityEmptyValue: "Passes through",
                isRecording: $isRecording,
                onRecord: record
            )
            .frame(width: 160)

            Button {
                isRecording = false
                errorMessage = nil
                eventTap.setRemap(nil, for: keyCode, inLayer: layerID)
            } label: {
                Text("Pass Through")
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 160)
            .controlSize(.small)
            .disabled(target == nil)

            Text(target == nil ? "Acts as \(baseLabel), as on Layer 0." : "Pass Through makes it act as \(baseLabel) again, as on Layer 0.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(width: 200)
        .onChange(of: isRecording) {
            if isRecording { errorMessage = nil }
        }
    }

    /// Returns `false` to keep recording after a key a layer can't use.
    private func record(_ recorded: KeyStroke) -> Bool {
        guard Layer.canActAs(recorded.keyCode) else {
            errorMessage = "A layer can't make keys act as \(KeyNames.name(for: recorded.keyCode)). Try another key."
            return false
        }
        eventTap.setRemap(recorded, for: keyCode, inLayer: layerID)
        return true
    }
}

// Popovers don't open in previews, so this shows the popover's content directly.

#Preview("Passes Through") {
    let eventTap = EventTap.preview()
    let layerID = eventTap.addLayer() ?? Layer.ID()
    return LayerKeyRemapView(eventTap: eventTap, layerID: layerID, keyCode: KeyCode.h, keyLabel: "H", baseLabel: "H")
}

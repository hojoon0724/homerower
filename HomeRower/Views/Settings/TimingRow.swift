import SwiftUI

/// A name with an info tooltip, and a slider for a millisecond value.
struct TimingRow: View {
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
        .padding(.trailing, 4)
    }
}

#Preview {
    @Previewable @State var tappingTerm = 200.0
    @Previewable @State var priorIdle = 150.0
    Form {
        TimingRow(
            title: "Hold threshold",
            detail: "How long to hold a home-row key before it acts as a modifier.",
            value: $tappingTerm,
            range: 100...500
        )
        TimingRow(
            title: "Fast-typing window",
            detail: "A home-row key pressed this soon after the previous key is treated as a letter.",
            value: $priorIdle,
            range: 0...300
        )
    }
    .formStyle(.grouped)
    .frame(width: 560)
}

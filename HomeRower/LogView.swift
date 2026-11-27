import SwiftUI

/// Shows the in-memory event log.
struct LogView: View {
    let eventTap: EventTap

    var body: some View {
        ScrollViewReader { proxy in
            List(Array(eventTap.logLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .onChange(of: eventTap.logLines.count) {
                if let last = eventTap.logLines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .toolbar {
            Button("Clear", systemImage: "trash") {
                eventTap.clearLog()
            }
        }
    }
}

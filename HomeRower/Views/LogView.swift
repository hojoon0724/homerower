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

#Preview("With Lines") {
    LogView(eventTap: .preview(logLines: [
        "Status: stopped → running",
        "Event tap running. Accessibility=true tap=enabled status=running",
        "↓ key 3  t=1024.512",
        "Hold leftCommand",
        "↓ key 12  t=1024.733",
        "↑ key 12  t=1024.801",
        "↑ key 3  t=1024.902",
        "Release leftCommand",
    ]))
    .frame(width: 420, height: 480)
}

#Preview("Empty") {
    LogView(eventTap: .preview())
        .frame(width: 420, height: 480)
}

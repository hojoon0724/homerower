import SwiftUI

/// Contents of the menu-bar menu.
struct MenuContentView: View {
    @Bindable var eventTap: EventTap
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Enabled", isOn: $eventTap.isEnabled)

        switch eventTap.status {
        case .running:
            Text("Event tap running")
        case .waitingForPermission:
            Text("Waiting for permission")
            Button("Set Up Permission…") {
                openWindow.bringToFront(.main)
            }
        case .stopped:
            Text("Stopped")
            Button("Start") {
                eventTap.start()
            }
        }

        Divider()

        Button("Open HomeRower…") {
            openWindow.bringToFront(.main)
        }
        Toggle("Log Key Events", isOn: $eventTap.logsKeyEvents)
        Button("Show Log") {
            openWindow.bringToFront(.log)
        }

        Divider()

        Button("Quit HomeRower") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// The real menu is drawn by the menu bar; these lay its items out in a column.

#Preview("Running") {
    VStack(alignment: .leading) {
        MenuContentView(eventTap: .preview())
    }
    .padding()
}

#Preview("Waiting for Permission") {
    VStack(alignment: .leading) {
        MenuContentView(eventTap: .preview(status: .waitingForPermission))
    }
    .padding()
}

#Preview("Stopped") {
    VStack(alignment: .leading) {
        MenuContentView(eventTap: .preview(status: .stopped))
    }
    .padding()
}

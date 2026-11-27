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
            Button("Open Privacy Settings…") {
                eventTap.openPrivacySettings()
            }
            Button("Retry") {
                eventTap.start()
            }
        case .stopped:
            Text("Stopped")
            Button("Start") {
                eventTap.start()
            }
        }

        Divider()

        Toggle("Log Key Events", isOn: $eventTap.logsKeyEvents)
        Button("Show Log") {
            openWindow(id: "log")
            NSApp.activate()
        }

        Divider()

        Button("Quit HomeRower") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

import SwiftUI

/// The main window's content: the permission screen until HomeRower is running,
/// then the settings.
struct RootView: View {
    let eventTap: EventTap
    let launchSettings: LaunchSettings

    var body: some View {
        Group {
            switch eventTap.status {
            case .running:
                MainView(eventTap: eventTap, launchSettings: launchSettings)
            case .waitingForPermission:
                PermissionView(eventTap: eventTap)
            case .stopped:
                // Only for the moment before the launch check finishes.
                ProgressView()
                    .frame(width: 480, height: 300)
            }
        }
        .animation(.default, value: eventTap.status)
        // Show a Dock icon only while this window is open.
        .onAppear {
            guard !AppEnvironment.isPreview else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            guard !AppEnvironment.isPreview else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

#Preview("Running") {
    RootView(eventTap: .preview(), launchSettings: .preview())
}

#Preview("Waiting for Permission") {
    RootView(eventTap: .preview(status: .waitingForPermission), launchSettings: .preview())
}

#Preview("Starting") {
    RootView(eventTap: .preview(status: .stopped), launchSettings: .preview())
}

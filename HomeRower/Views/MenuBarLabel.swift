import SwiftUI

/// The menu bar icon. It's the one view that always exists, even with every window
/// closed, so it opens the main window at launch (if the user wants that, or permission
/// is missing) and brings up the permission screen if access is turned off.
struct MenuBarLabel: View {
    let eventTap: EventTap
    let launchSettings: LaunchSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // A template image, so the menu bar tints it for light and dark menu bars.
        Image(.menuBarIcon)
            .accessibilityLabel("HomeRower")
            .onAppear {
                guard !launchSettings.didHandleLaunch else { return }
                launchSettings.didHandleLaunch = true
                // If the launch check already found permission missing, the status
                // change below happened before this view existed, so handle it here.
                if launchSettings.opensSettingsAtLaunch || eventTap.status == .waitingForPermission {
                    openWindow.bringToFront(.main)
                }
            }
            .onChange(of: eventTap.status) { oldStatus, newStatus in
                // Running → waiting means access was turned off or removed. (Stopped →
                // waiting is the same thing seen mid-way, or the launch check.)
                guard oldStatus != newStatus, newStatus == .waitingForPermission else { return }
                openWindow.bringToFront(.main)
            }
    }
}

#Preview {
    MenuBarLabel(eventTap: .preview(), launchSettings: .preview())
        .padding()
}

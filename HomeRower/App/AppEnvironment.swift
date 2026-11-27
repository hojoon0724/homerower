import AppKit
import SwiftUI
import os

/// Facts about the process HomeRower is running in.
nonisolated enum AppEnvironment {
    /// Running inside an Xcode preview host, which must not touch the Dock icon or Login Items.
    static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

nonisolated extension Logger {
    /// A logger in HomeRower's subsystem. Read it with
    /// `log show --predicate 'subsystem == "<bundle ID>"'`.
    static func homeRower(category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "HomeRower", category: category)
    }
}

/// HomeRower's windows, by scene ID.
enum AppWindow: String {
    case main
    case log
}

extension OpenWindowAction {
    /// Opens a window and brings it in front of every other app's windows.
    func bringToFront(_ window: AppWindow) {
        callAsFunction(id: window.rawValue)
        NSApp.activate()
        // SwiftUI names the window after the scene ID, with a suffix.
        if let nsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(window.rawValue) == true }) {
            nsWindow.makeKeyAndOrderFront(nil)
            nsWindow.orderFrontRegardless()
        }
    }
}

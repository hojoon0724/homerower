import AppKit
import ApplicationServices

/// HomeRower's entry in Privacy & Security > Accessibility.
///
/// The user adds HomeRower to the list by hand. In the sandbox the app can't add itself:
/// `AXIsProcessTrustedWithOptions` never reaches tccd, and `CGRequestPostEventAccess`
/// records a denied PostEvent entry that the list's switch can't change and that makes
/// macOS refuse the tap.
enum PrivacyAccess {
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static var isAccessibilityOn: Bool {
        AXIsProcessTrusted()
    }

    static var appURL: URL { Bundle.main.bundleURL }

    static var appIcon: NSImage { NSWorkspace.shared.icon(forFile: appURL.path) }

    static var diagnostics: String {
        "Accessibility=\(AXIsProcessTrusted())"
    }
}

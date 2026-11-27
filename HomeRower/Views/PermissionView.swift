import SwiftUI

/// Shown in the main window until HomeRower has the access it needs. Once access is
/// on, the tap starts by itself and the window switches to the settings.
struct PermissionView: View {
    let eventTap: EventTap

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow HomeRower to Use Your Keyboard")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(explanation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                step(1, "Click **Open System Settings**. If macOS shows an alert, choose **Open System Settings** there.")
                step(2, "Turn on **HomeRower** in the list that opens.")
                step(3, "HomeRower will start when it's ready.")
            }

            statusRow

            HStack {
                Button("Quit HomeRower") {
                    NSApp.terminate(nil)
                }
                Spacer()
                Button("Open System Settings") {
                    eventTap.requestPermission()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 480)
    }

    private var explanation: String {
        switch eventTap.neededPermission {
        case .accessibility:
            "HomeRower needs Accessibility access to read your key presses and send modifiers in their place."
        case .inputMonitoring:
            "Accessibility is on. On this Mac, HomeRower also needs Input Monitoring to read key presses."
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.monospacedDigit().weight(.semibold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Live feedback: waiting, resetting, or stuck with a way out.
    @ViewBuilder
    private var statusRow: some View {
        if eventTap.isResettingPermission {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Resetting HomeRower's permission…")
            }
            .foregroundStyle(.secondary)
        } else if eventTap.needsManualRetry {
            WarningBox(
                title: "HomeRower stopped to keep your keyboard working.",
                message: "macOS stopped accepting HomeRower's key events, which happens when HomeRower is removed from the list. Make sure HomeRower is in the list and turned on, then click Try Again."
            ) {
                HStack {
                    Button("Try Again") {
                        eventTap.retryAfterFailSafe()
                    }
                    resetPermissionButton
                }
            }
        } else if eventTap.isTapBlocked {
            WarningBox(
                title: "HomeRower is turned on, but macOS isn't letting it start.",
                message: "This usually happens after HomeRower was rebuilt or moved. Resetting removes the old entry so you can turn it on again."
            ) {
                resetPermissionButton
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for \(eventTap.neededPermission.displayName) access…")
            }
            .foregroundStyle(.secondary)
        }
    }

    private var resetPermissionButton: some View {
        Button("Reset Permission") {
            Task { await eventTap.resetPermission() }
        }
    }
}

/// An orange box explaining a problem, with buttons to fix it.
private struct WarningBox<Actions: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Accessibility") {
    PermissionView(eventTap: .preview(status: .waitingForPermission))
}

#Preview("Input Monitoring") {
    PermissionView(eventTap: .preview(status: .waitingForPermission, neededPermission: .inputMonitoring))
}

#Preview("Stopped by Fail-Safe") {
    PermissionView(eventTap: .preview(status: .waitingForPermission, needsManualRetry: true))
}

#Preview("Tap Blocked") {
    PermissionView(eventTap: .preview(status: .waitingForPermission, isTapBlocked: true))
}

#Preview("Resetting Permission") {
    PermissionView(eventTap: .preview(status: .waitingForPermission, isResettingPermission: true))
}

#Preview("Warning Box") {
    WarningBox(title: "Something went wrong.", message: "Well, this never happened before, I swear.") {
        HStack {
            HStack {
                Button("Ignore") {}
                Button("Report bug") {}
            }
            Spacer()
            HStack {
                Button("Quit") {}
            }
        }
    }
    .padding()
    .frame(width: 480)
}

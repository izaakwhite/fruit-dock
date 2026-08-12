import AppKit
import ApplicationServices

/// Deep links into System Settings, and the Accessibility permission check.
///
/// macOS will not let an app change these on the user's behalf, so the most
/// it can do is land them on the right pane. Making that one click is the
/// difference between a setting people change and one they abandon.
@MainActor
enum SystemSettings {

    /// Panes the dock ever needs to send someone to.
    enum Pane {
        case accessibilityPrivacy
        case dock
        case displays
        case accessibilityDisplay

        /// These `x-apple.systempreferences:` URLs are the documented way in,
        /// but the pane identifiers have shifted across releases. `open(_:)`
        /// falls back to System Settings' front door if one stops resolving,
        /// so a stale identifier degrades to "wrong pane" rather than
        /// "nothing happens".
        var url: URL? {
            let base = "x-apple.systempreferences:"
            return switch self {
            case .accessibilityPrivacy:
                URL(string: base + "com.apple.preference.security?Privacy_Accessibility")
            case .accessibilityDisplay:
                URL(string: base + "com.apple.preference.universalaccess?Seeing_Display")
            case .dock:
                URL(string: base + "com.apple.preference.dock")
            case .displays:
                URL(string: base + "com.apple.preference.displays")
            }
        }
    }

    static func open(_ pane: Pane) {
        guard let url = pane.url else {
            openSystemSettings()
            return
        }
        if !NSWorkspace.shared.open(url) {
            openSystemSettings()
        }
    }

    private static func openSystemSettings() {
        // Bundle identifier rather than a path: System Preferences was
        // renamed to System Settings, and the identifier outlived the name.
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences"
        ) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: - Accessibility permission

    /// Whether this process may control other applications' windows.
    ///
    /// Checked without prompting, so it is safe to call whenever the UI needs
    /// to reflect current state.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS to show its own Accessibility permission prompt.
    ///
    /// The system dialog is preferable to a custom one — it is the wording
    /// people already recognise, and it offers the direct route to the pane.
    /// No-op when permission is already granted.
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        // The key is spelled out rather than read from
        // `kAXTrustedCheckOptionPrompt`, which Swift 6 rejects as a mutable
        // global. Its value is this exact string and is part of the framework's
        // published interface, so hardcoding it is stable.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

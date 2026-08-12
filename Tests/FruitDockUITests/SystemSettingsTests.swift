import Foundation
import Testing
@testable import FruitDockUI

/// `SystemSettings.Pane.url` is pure string construction — no `NSWorkspace`
/// call, no window, so each pane's deep link can be checked directly against
/// the exact string macOS expects.
///
/// `open(_:)`'s fallback to System Settings' front door when a URL fails to
/// resolve is a separate, `NSWorkspace`-driven code path and is not covered
/// here — it needs a live `NSWorkspace` to observe, not a unit test.
@MainActor
@Suite("System Settings deep links")
struct SystemSettingsTests {

    @Test("Dock & Menu Bar opens the dock preference pane")
    func dockPaneURL() {
        #expect(
            SystemSettings.Pane.dock.url?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.dock"
        )
    }

    @Test("Displays opens the displays preference pane")
    func displaysPaneURL() {
        #expect(
            SystemSettings.Pane.displays.url?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.displays"
        )
    }

    @Test("Accessibility: Display opens the Seeing/Display accessibility pane")
    func accessibilityDisplayPaneURL() {
        #expect(
            SystemSettings.Pane.accessibilityDisplay.url?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display"
        )
    }

    @Test("Privacy: Accessibility opens the security preference pane's Accessibility section")
    func accessibilityPrivacyPaneURL() {
        #expect(
            SystemSettings.Pane.accessibilityPrivacy.url?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    @Test("Every pane resolves to a URL — none fall through to the front-door fallback")
    func everyPaneResolves() {
        let panes: [SystemSettings.Pane] = [.accessibilityPrivacy, .dock, .displays, .accessibilityDisplay]
        #expect(panes.allSatisfy { $0.url != nil })
    }
}

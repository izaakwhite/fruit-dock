import AppKit
import FruitDockCore

/// The app's single view of whether it may move other applications' windows.
///
/// Without this permission the dock still works — clicking an icon activates
/// or launches the app exactly as before — but macOS, not the user, picks the
/// display. That is a degraded feature rather than a broken one, and the whole
/// job of this type is to make the degradation visible instead of silent.
/// Before it existed, `WindowPlacer` returned early on a failed
/// `AXIsProcessTrusted()` and nothing anywhere said so.
///
/// Owns no policy of its own: the never-nag rule is a pure decision in
/// `FruitDockCore` so it can be tested without a dialog on screen.
@MainActor
final class AccessibilityPermission {
    private var policy = AccessibilityPromptPolicy()

    /// Read live rather than cached. The user can grant or revoke this in
    /// System Settings while the app runs, and there is no notification for
    /// it — a value captured at launch would be wrong for the rest of the
    /// session.
    var isGranted: Bool { SystemSettings.hasAccessibilityPermission }

    /// Shows the system prompt if this trigger warrants one, and otherwise
    /// does nothing at all.
    func consider(_ trigger: AccessibilityPromptTrigger) {
        guard policy.decide(isTrusted: isGranted, trigger: trigger) == .showSystemPrompt
        else { return }
        SystemSettings.requestAccessibilityPermission()
    }

    /// The menu route: prompt *and* open the pane.
    ///
    /// Both, because either alone has a hole. macOS shows its dialog only
    /// once per binary until the permission database is reset, so a second
    /// click on the menu item would do nothing visible; and the dialog's own
    /// button is the flow people recognise, so skipping it in favour of the
    /// pane loses the familiar wording. Doing both means the click always
    /// lands somewhere useful.
    func requestFromMenu() {
        consider(.userRequest)
        SystemSettings.open(.accessibilityPrivacy)
    }
}

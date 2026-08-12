/// Why the app is considering asking for Accessibility permission.
public enum AccessibilityPromptTrigger: Hashable, Sendable {
    /// The app started and noticed it cannot place windows.
    case launch

    /// A click asked for placement and it was unavailable.
    case placementAttempt

    /// The user chose the menu item. Not a nag — they asked.
    case userRequest
}

public enum AccessibilityPromptDecision: Hashable, Sendable {
    case showSystemPrompt
    case staySilent
}

/// When it is acceptable to put the system permission dialog on screen.
///
/// A menu-bar agent that asks for Accessibility every time something needs it
/// is a menu-bar agent people quit. The rule is at most one unsolicited prompt
/// per launch; after that the only remaining route is the menu item, which the
/// user has to choose, and which is therefore never a nag.
///
/// A decision rather than a side effect so the never-nag rule can be tested
/// without a dialog appearing on a real screen — the code path that would
/// otherwise be verified by nobody.
public struct AccessibilityPromptPolicy: Hashable, Sendable {

    /// Deliberately per-launch and not persisted. Permission can be revoked in
    /// System Settings between runs, and a stored "already asked" would then
    /// leave a user with a silently degraded app and no prompt to explain it.
    public private(set) var hasPromptedThisLaunch = false

    public init() {}

    public mutating func decide(
        isTrusted: Bool,
        trigger: AccessibilityPromptTrigger
    ) -> AccessibilityPromptDecision {
        // Already granted: there is nothing to ask for, and macOS would show
        // nothing anyway.
        guard !isTrusted else { return .staySilent }

        if trigger != .userRequest && hasPromptedThisLaunch {
            return .staySilent
        }

        hasPromptedThisLaunch = true
        return .showSystemPrompt
    }
}

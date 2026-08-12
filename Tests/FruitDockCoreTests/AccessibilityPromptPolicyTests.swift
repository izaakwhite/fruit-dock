import Testing
@testable import FruitDockCore

/// The never-nag rule.
///
/// This is a decision rather than a side effect precisely so it can be checked
/// here, without a permission dialog appearing on a real screen — otherwise it
/// is the kind of code path nobody verifies until a user complains that the
/// menu-bar app keeps asking.
@Suite("Accessibility prompt policy")
struct AccessibilityPromptPolicyTests {

    @Test("A missing permission is raised once when the app launches")
    func promptsOnLaunch() {
        var policy = AccessibilityPromptPolicy()

        #expect(policy.decide(isTrusted: false, trigger: .launch) == .showSystemPrompt)
    }

    @Test("A placement attempt raises it when launch did not")
    func promptsOnFirstPlacement() {
        // Nothing prompts at launch on a single-display Mac, since there is
        // nowhere else for an app to open. Plugging in a second display and
        // clicking is the first moment the permission matters.
        var policy = AccessibilityPromptPolicy()

        #expect(policy.decide(isTrusted: false, trigger: .placementAttempt) == .showSystemPrompt)
    }

    @Test("A second click in the same launch says nothing")
    func doesNotNag() {
        var policy = AccessibilityPromptPolicy()
        _ = policy.decide(isTrusted: false, trigger: .launch)

        // Every click on a dock icon reaches the placement path. Prompting on
        // each one would make the app unusable while permission is denied.
        #expect(policy.decide(isTrusted: false, trigger: .placementAttempt) == .staySilent)
        #expect(policy.decide(isTrusted: false, trigger: .launch) == .staySilent)
    }

    @Test("Granted permission is never asked about")
    func silentWhenGranted() {
        var policy = AccessibilityPromptPolicy()

        #expect(policy.decide(isTrusted: true, trigger: .launch) == .staySilent)
        #expect(policy.decide(isTrusted: true, trigger: .placementAttempt) == .staySilent)
        #expect(policy.decide(isTrusted: true, trigger: .userRequest) == .staySilent)
        // Nothing was spent, so a later revocation still gets its one prompt.
        #expect(!policy.hasPromptedThisLaunch)
    }

    @Test("Choosing the menu item prompts however often it is chosen")
    func userRequestAlwaysPrompts() {
        var policy = AccessibilityPromptPolicy()
        _ = policy.decide(isTrusted: false, trigger: .launch)

        // Asking is not nagging when the user is the one who asked.
        #expect(policy.decide(isTrusted: false, trigger: .userRequest) == .showSystemPrompt)
        #expect(policy.decide(isTrusted: false, trigger: .userRequest) == .showSystemPrompt)
    }

    @Test("A permission revoked between launches is raised again")
    func newLaunchPromptsAgain() {
        var first = AccessibilityPromptPolicy()
        _ = first.decide(isTrusted: true, trigger: .launch)

        // A fresh policy models the next launch. Persisting "already asked"
        // would leave someone who revoked the permission with a silently
        // degraded app and nothing to explain it.
        var second = AccessibilityPromptPolicy()
        #expect(second.decide(isTrusted: false, trigger: .launch) == .showSystemPrompt)
    }
}

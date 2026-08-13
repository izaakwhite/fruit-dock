/// What the Accessibility API reports about one of an application's windows.
///
/// A flattened description rather than the `AXUIElement` itself, so the
/// decision below can be exercised without a running application.
public struct WindowCandidate: Hashable, Sendable {
    /// The window the app itself nominates as main — the one that comes
    /// forward when the app is activated.
    public var isMain: Bool
    public var isMinimised: Bool
    public var isFullScreen: Bool

    /// Whether the Accessibility API reports the position attribute as
    /// settable. This is how an app that simply refuses to be moved announces
    /// itself, and asking is quieter than trying and logging the failure.
    public var canBeMoved: Bool

    public init(
        isMain: Bool = false,
        isMinimised: Bool = false,
        isFullScreen: Bool = false,
        canBeMoved: Bool = true
    ) {
        self.isMain = isMain
        self.isMinimised = isMinimised
        self.isFullScreen = isFullScreen
        self.canBeMoved = canBeMoved
    }

    /// Full-screen windows own a Space of their own and their position is not
    /// the app's to give; minimised ones are in the Dock, where a new position
    /// would take effect invisibly and surprise the user on restore.
    public var isEligible: Bool {
        canBeMoved && !isMinimised && !isFullScreen
    }
}

public enum WindowPlacementOutcome: Hashable, Sendable {
    /// Index into the candidates that were supplied.
    case move(Int)

    /// There are windows, but none that should be moved. Stop asking.
    case nothingToMove

    /// The app has not settled yet. Worth another look shortly.
    case waitForWindows
}

/// Decides *which* of an application's windows a dock click should move.
public enum WindowPlacementRules {

    /// Picks at most one window, never all of them.
    ///
    /// The obvious implementation — move every window the app owns — is
    /// destructive. Someone with six browser windows arranged across two
    /// displays loses that arrangement to a single click, stacked into one
    /// centred pile, with no undo. The click means "bring this app here", and
    /// what the user sees arrive is the main window; moving the rest is
    /// collateral damage they did not ask for and cannot reverse.
    ///
    /// So: move the app's own nominated main window, and nothing else. When
    /// the app nominates none but owns exactly one window, that window is
    /// unambiguously the one meant — this is the freshly launched case, and
    /// the common one. When it nominates none and owns several, refuse rather
    /// than guess; the attribute usually appears a moment later, so this is
    /// reported as "not settled" and the caller may look again.
    ///
    /// An ineligible main window is a deliberate state, not a race: the user
    /// minimised it or sent it full-screen. That is `nothingToMove`, and no
    /// amount of retrying will change it.
    public static func windowToMove(among candidates: [WindowCandidate]) -> WindowPlacementOutcome {
        guard !candidates.isEmpty else { return .waitForWindows }

        if let main = candidates.firstIndex(where: \.isMain) {
            return candidates[main].isEligible ? .move(main) : .nothingToMove
        }

        guard candidates.count == 1 else { return .waitForWindows }
        return candidates[0].isEligible ? .move(0) : .nothingToMove
    }

    /// Picks the window a dock click should un-minimise, if any.
    ///
    /// Clicking a dock icon means "bring this app up", and Apple's Dock honours
    /// that by restoring a minimised window. Activating the app alone does not:
    /// the app comes forward with no window, which reads as the click having
    /// done nothing at all.
    ///
    /// Deliberately narrower than "restore everything". Someone with several
    /// windows minimised chose to put each one away, and returning all of them
    /// at once is as destructive as moving every window would be. So: restore
    /// the nominated main window if it is minimised, otherwise the sole
    /// minimised window, and otherwise nothing.
    ///
    /// Only ever called for an explicit click. Minimised state is respected
    /// everywhere else — see `WindowCandidate.isEligible`.
    public static func windowToRestore(among candidates: [WindowCandidate]) -> Int? {
        // An app with any window already on screen is not the case this is for:
        // activation will bring that window forward on its own, and restoring
        // something the user put away would be unasked for.
        guard !candidates.isEmpty, candidates.allSatisfy(\.isMinimised) else { return nil }

        if let main = candidates.firstIndex(where: \.isMain) { return main }

        return candidates.count == 1 ? 0 : nil
    }
}

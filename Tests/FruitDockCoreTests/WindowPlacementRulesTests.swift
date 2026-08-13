import Testing
@testable import FruitDockCore

/// The rule that decides how much of someone's layout a single click is
/// allowed to rearrange.
///
/// The first version moved every window the app owned, which is unrecoverable
/// for anyone who had arranged several. These cases pin the narrower promise:
/// one window, or none.
@Suite("Window placement rules")
struct WindowPlacementRulesTests {

    let main = WindowCandidate(isMain: true)
    let other = WindowCandidate()

    @Test("An app that has not opened a window yet is worth another look")
    func noWindowsYet() {
        // The freshly launched case. A single attempt lands before there is
        // anything to move, so this must be distinguishable from "there is
        // nothing here I should touch".
        #expect(WindowPlacementRules.windowToMove(among: []) == .waitForWindows)
    }

    @Test("Only the main window moves, never every window the app owns")
    func onlyTheMainWindow() {
        let outcome = WindowPlacementRules.windowToMove(among: [other, main, other])

        // Six browser windows arranged across two displays must survive a
        // click on the browser's icon.
        #expect(outcome == .move(1))
    }

    @Test("A lone window is moved before the app nominates a main one")
    func singleWindowNeedsNoNomination() {
        // Right after launch the main-window attribute is often still unset,
        // and with one window there is nothing to be ambiguous about.
        #expect(WindowPlacementRules.windowToMove(among: [other]) == .move(0))
    }

    @Test("Several windows and no nominated main is not a licence to guess")
    func severalWindowsNoMain() {
        // The attribute usually appears a moment later. Picking one at random
        // in the meantime would move the wrong window and there is no undo.
        #expect(WindowPlacementRules.windowToMove(among: [other, other]) == .waitForWindows)
    }

    @Test("A minimised main window is left in the Dock where the user put it")
    func minimisedMainWindow() {
        let minimised = WindowCandidate(isMain: true, isMinimised: true)

        // Setting a position on a minimised window takes effect invisibly and
        // surprises the user when they restore it.
        #expect(WindowPlacementRules.windowToMove(among: [minimised]) == .nothingToMove)
    }

    @Test("A full-screen main window owns its Space and is left alone")
    func fullScreenMainWindow() {
        let fullScreen = WindowCandidate(isMain: true, isFullScreen: true)
        #expect(WindowPlacementRules.windowToMove(among: [fullScreen]) == .nothingToMove)
    }

    @Test("An app that refuses to be moved is not asked twice")
    func immovableWindow() {
        let immovable = WindowCandidate(isMain: true, canBeMoved: false)

        // Distinct from waitForWindows: a settable attribute does not become
        // settable by asking again, so this must end the retries rather than
        // spend four seconds and a log line per click discovering it.
        #expect(WindowPlacementRules.windowToMove(among: [immovable]) == .nothingToMove)
    }

    @Test("A deliberately minimised main window is not swapped for a movable sibling")
    func minimisedMainIsNotSubstituted() {
        let minimised = WindowCandidate(isMain: true, isMinimised: true)

        // The app said which window matters. Moving a different one because
        // that one was inconvenient is exactly the destructive behaviour this
        // rule exists to prevent.
        #expect(WindowPlacementRules.windowToMove(among: [minimised, other]) == .nothingToMove)
    }

    @Test("A minimised sibling does not stop the main window moving")
    func minimisedSiblingIsIgnored() {
        let minimised = WindowCandidate(isMinimised: true)
        #expect(WindowPlacementRules.windowToMove(among: [minimised, main]) == .move(1))
    }

    @Test("A lone minimised window ends the attempt rather than prolonging it")
    func loneMinimisedWindow() {
        let minimised = WindowCandidate(isMinimised: true)
        #expect(WindowPlacementRules.windowToMove(among: [minimised]) == .nothingToMove)
    }

    // MARK: - Restoring a minimised window

    @Test("A lone minimised window is restored by a click")
    func loneMinimisedWindowIsRestored() {
        // Reported from use: clicking an app whose only window was minimised
        // activated it with nothing on screen, so the click looked inert.
        // `activate()` does not un-minimise.
        let minimised = WindowCandidate(isMinimised: true)
        #expect(WindowPlacementRules.windowToRestore(among: [minimised]) == 0)
    }

    @Test("The main window is the one restored when several are minimised")
    func mainMinimisedWindowIsRestored() {
        let other = WindowCandidate(isMinimised: true)
        let main = WindowCandidate(isMain: true, isMinimised: true)

        #expect(WindowPlacementRules.windowToRestore(among: [other, main]) == 1)
    }

    @Test("Several minimised windows with none nominated restores nothing")
    func ambiguousMinimisedWindowsRestoreNothing() {
        // Each was put away deliberately. Guessing brings back the wrong one,
        // and bringing back all of them is as destructive as moving them all.
        let windows = [WindowCandidate(isMinimised: true), WindowCandidate(isMinimised: true)]
        #expect(WindowPlacementRules.windowToRestore(among: windows) == nil)
    }

    @Test("Nothing is restored while any window is still on screen")
    func onScreenWindowSuppressesRestore() {
        // Activation brings the visible window forward by itself. Un-minimising
        // another one here would return something the user had put away and
        // never asked for.
        let minimised = WindowCandidate(isMinimised: true)
        let onScreen = WindowCandidate(isMain: true)

        #expect(WindowPlacementRules.windowToRestore(among: [minimised, onScreen]) == nil)
    }

    @Test("An app with no windows has nothing to restore")
    func noWindowsRestoresNothing() {
        #expect(WindowPlacementRules.windowToRestore(among: []) == nil)
    }

    @Test("A full-screen window is not treated as minimised")
    func fullScreenIsNotRestored() {
        let fullScreen = WindowCandidate(isMain: true, isFullScreen: true)
        #expect(WindowPlacementRules.windowToRestore(among: [fullScreen]) == nil)
    }
}

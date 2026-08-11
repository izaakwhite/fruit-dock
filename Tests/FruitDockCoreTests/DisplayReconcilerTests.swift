import Testing
@testable import FruitDockCore

/// Every scenario here would otherwise require physically unplugging a
/// monitor. That is the entire reason the reconciler is a pure function.
@Suite("Display reconciliation")
struct DisplayReconcilerTests {

    // Named displays keep the test bodies readable.
    let builtIn = DisplayInfo(id: DisplayID(1), name: "Built-in Display", isPrimary: true)
    let external = DisplayInfo(id: DisplayID(2), name: "DELL U2720Q")
    let secondExternal = DisplayInfo(id: DisplayID(3), name: "LG UltraFine")

    @Test("A newly connected display gains a panel")
    func newDisplayGainsPanel() {
        let plan = DisplayReconciler.plan(
            connected: [builtIn, external],
            existingPanels: [builtIn.id],
            configuration: .default
        )

        #expect(plan.toCreate == [external.id])
        #expect(plan.toRemove.isEmpty)
        #expect(plan.toUpdate == [builtIn.id])
    }

    @Test("Unplugging a display removes its panel — FR-1.3")
    func disconnectRemovesPanel() {
        let plan = DisplayReconciler.plan(
            connected: [builtIn],
            existingPanels: [builtIn.id, external.id],
            configuration: .default
        )

        #expect(plan.toRemove == [external.id])
        #expect(plan.toCreate.isEmpty)
    }

    @Test("Reconnecting a display restores its panel — FR-1.4")
    func reconnectRestoresPanel() {
        let plan = DisplayReconciler.plan(
            connected: [builtIn, external],
            existingPanels: [builtIn.id],
            configuration: .default
        )

        #expect(plan.toCreate == [external.id])
    }

    @Test("Disabling a display removes its panel without disconnecting it")
    func disablingRemovesPanel() {
        var config = DockConfiguration.default
        config.setEnabled(false, for: external.id)

        let plan = DisplayReconciler.plan(
            connected: [builtIn, external],
            existingPanels: [builtIn.id, external.id],
            configuration: config
        )

        #expect(plan.toRemove == [external.id])
        #expect(plan.toUpdate == [builtIn.id])
    }

    @Test("A disabled display never gains a panel on reconnect")
    func disabledDisplayStaysDisabled() {
        var config = DockConfiguration.default
        config.setEnabled(false, for: external.id)

        let plan = DisplayReconciler.plan(
            connected: [builtIn, external],
            existingPanels: [],
            configuration: config
        )

        #expect(plan.toCreate == [builtIn.id])
        #expect(!plan.toCreate.contains(external.id))
    }

    @Test("An unknown display is enabled by default")
    func unknownDisplayDefaultsToEnabled() {
        let plan = DisplayReconciler.plan(
            connected: [secondExternal],
            existingPanels: [],
            configuration: .default
        )

        #expect(plan.toCreate == [secondExternal.id])
    }

    @Test("Reconciling an already-correct state requests no changes")
    func steadyStateIsIdempotent() {
        let config = DockConfiguration.default
        let connected = [builtIn, external]

        let first = DisplayReconciler.plan(
            connected: connected,
            existingPanels: [],
            configuration: config
        )
        // Apply the first plan, then reconcile again from the resulting state.
        let second = DisplayReconciler.plan(
            connected: connected,
            existingPanels: first.toCreate,
            configuration: config
        )

        #expect(second.toCreate.isEmpty)
        #expect(second.toRemove.isEmpty)
        #expect(second.toUpdate == [builtIn.id, external.id])
    }

    @Test("Losing every display tears down every panel — NFR-5")
    func allDisplaysGoneRemovesEverything() {
        let plan = DisplayReconciler.plan(
            connected: [],
            existingPanels: [builtIn.id, external.id, secondExternal.id],
            configuration: .default
        )

        #expect(plan.toRemove == [builtIn.id, external.id, secondExternal.id])
        #expect(plan.toCreate.isEmpty)
        #expect(plan.toUpdate.isEmpty)
    }

    @Test("Swapping one display for another in a single event")
    func simultaneousConnectAndDisconnect() {
        // Docking stations can replace the whole display set between two
        // notifications, so create and remove must be handled in one pass.
        let plan = DisplayReconciler.plan(
            connected: [builtIn, secondExternal],
            existingPanels: [builtIn.id, external.id],
            configuration: .default
        )

        #expect(plan.toCreate == [secondExternal.id])
        #expect(plan.toRemove == [external.id])
        #expect(plan.toUpdate == [builtIn.id])
    }

    @Test("No panel on the display that already has Apple's Dock")
    func skipsDisplayHostingSystemDock() {
        // Two docks on one screen is the bug this prevents.
        let hosting = DisplayInfo(
            id: builtIn.id, name: builtIn.name, isPrimary: true, hostsSystemDock: true)

        let plan = DisplayReconciler.plan(
            connected: [hosting, external],
            existingPanels: [],
            configuration: .default
        )

        #expect(plan.toCreate == [external.id])
        #expect(!plan.toCreate.contains(builtIn.id))
    }

    @Test("Our dock follows Apple's Dock between displays")
    func panelMovesWhenSystemDockMoves() {
        // macOS moves its Dock to whichever display the cursor pushes into,
        // with no display being connected or disconnected. Our panels have to
        // trade places in response.
        let dockOnBuiltIn = [
            DisplayInfo(id: builtIn.id, name: builtIn.name, isPrimary: true, hostsSystemDock: true),
            DisplayInfo(id: external.id, name: external.name),
        ]
        let dockOnExternal = [
            DisplayInfo(id: builtIn.id, name: builtIn.name, isPrimary: true),
            DisplayInfo(id: external.id, name: external.name, hostsSystemDock: true),
        ]

        // Steady state: our panel is on the external only.
        let before = DisplayReconciler.plan(
            connected: dockOnBuiltIn, existingPanels: [], configuration: .default)
        #expect(before.toCreate == [external.id])

        // The user drags the system Dock across.
        let after = DisplayReconciler.plan(
            connected: dockOnExternal,
            existingPanels: [external.id],
            configuration: .default
        )

        #expect(after.toCreate == [builtIn.id])   // we take over the vacated screen
        #expect(after.toRemove == [external.id])  // and vacate the one it took
    }

    @Test("Avoidance can be switched off")
    func avoidanceIsOptional() {
        var config = DockConfiguration.default
        config.avoidsSystemDockDisplay = false

        let hosting = DisplayInfo(
            id: builtIn.id, name: builtIn.name, isPrimary: true, hostsSystemDock: true)

        let plan = DisplayReconciler.plan(
            connected: [hosting, external],
            existingPanels: [],
            configuration: config
        )

        #expect(plan.toCreate == [builtIn.id, external.id])
    }

    @Test("A disabled display stays disabled even without Apple's Dock on it")
    func explicitDisableBeatsAvoidance() {
        var config = DockConfiguration.default
        config.setEnabled(false, for: external.id)

        let hosting = DisplayInfo(
            id: builtIn.id, name: builtIn.name, isPrimary: true, hostsSystemDock: true)

        let plan = DisplayReconciler.plan(
            connected: [hosting, external],
            existingPanels: [],
            configuration: config
        )

        // Nowhere left to draw: one display has Apple's Dock, the other is off.
        #expect(plan.toCreate.isEmpty)
    }

    @Test("Identity is by display ID, not by position in the list")
    func identityIsNotPositional() {
        // The same displays reported in reverse order must produce no changes.
        // Indexing into the screen list instead of keying by ID would fail here.
        let config = DockConfiguration.default

        let forward = DisplayReconciler.plan(
            connected: [builtIn, external],
            existingPanels: [builtIn.id, external.id],
            configuration: config
        )
        let reversed = DisplayReconciler.plan(
            connected: [external, builtIn],
            existingPanels: [builtIn.id, external.id],
            configuration: config
        )

        #expect(forward == reversed)
        #expect(forward.isEmpty == false)  // updates are expected
        #expect(forward.toCreate.isEmpty)
        #expect(forward.toRemove.isEmpty)
    }
}

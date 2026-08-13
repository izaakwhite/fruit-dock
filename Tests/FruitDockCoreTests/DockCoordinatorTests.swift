import Testing
@testable import FruitDockCore

/// Tests the coordinator's *wiring* rather than its arithmetic.
///
/// `DisplayReconciler` and `DockContentBuilder` are already covered as pure
/// functions, and they were correct while the feature they drive was entirely
/// non-functional — because nothing called them. These tests exist to catch
/// that class of failure.
@MainActor
@Suite("Dock coordinator")
struct DockCoordinatorTests {

    /// Assembles a coordinator over fakes, returning the parts a test needs.
    private func makeSubject(
        displays: [DisplayInfo] = [Fixture.builtIn, Fixture.external],
        running: [ApplicationInfo] = [],
        configuration: DockConfiguration? = nil,
        systemDock: FakeSystemDock = FakeSystemDock(),
        catalog: FakeApplicationCatalog = FakeApplicationCatalog()
    ) -> (
        coordinator: DockCoordinator,
        displays: FakeDisplayProvider,
        apps: FakeApplicationProvider,
        store: FakeConfigurationStore,
        presenter: FakePresenter,
        systemDock: FakeSystemDock,
        catalog: FakeApplicationCatalog
    ) {
        let displayProvider = FakeDisplayProvider(displays)
        let appProvider = FakeApplicationProvider(running)
        let store = FakeConfigurationStore(configuration)
        let presenter = FakePresenter()

        let coordinator = DockCoordinator(
            displayProvider: displayProvider,
            applicationProvider: appProvider,
            systemDock: systemDock,
            applicationCatalog: catalog,
            store: store,
            presenter: presenter
        )
        return (coordinator, displayProvider, appProvider, store, presenter, systemDock, catalog)
    }

    // MARK: - Wiring

    @Test("start() subscribes to both providers")
    func startSubscribes() {
        let subject = makeSubject()
        #expect(!subject.displays.isObserved)

        subject.coordinator.start()

        // A coordinator that never subscribes can never react — the exact
        // shape of the display-follows-Dock bug.
        #expect(subject.displays.isObserved)
        #expect(subject.apps.isObserved)
    }

    @Test("A display change triggers reconciliation")
    func displayChangeReconciles() {
        // Regression test. The reconciler was correct and covered; nothing
        // invoked it, so the feature never worked.
        let subject = makeSubject(displays: [Fixture.builtIn])
        subject.coordinator.start()
        #expect(subject.presenter.presentedDisplays == [Fixture.builtIn.id])

        subject.displays.simulateChange(to: [Fixture.builtIn, Fixture.external])

        #expect(subject.presenter.presentedDisplays == [Fixture.builtIn.id, Fixture.external.id])
    }

    @Test("Our dock trades places when the system Dock moves")
    func followsSystemDock() {
        // No display connects or disconnects here — only which one hosts
        // Apple's Dock changes.
        let subject = makeSubject(displays: [Fixture.builtInWithDock, Fixture.external])
        subject.coordinator.start()
        #expect(subject.presenter.presentedDisplays == [Fixture.external.id])

        let dockMovedToExternal = DisplayInfo(
            id: Fixture.external.id, name: Fixture.external.name, hostsSystemDock: true)
        subject.displays.simulateChange(to: [Fixture.builtIn, dockMovedToExternal])

        #expect(subject.presenter.presentedDisplays == [Fixture.builtIn.id])
    }

    @Test("A running-apps change re-renders contents")
    func runningAppsChangeRenders() {
        let subject = makeSubject(displays: [Fixture.builtIn], running: [Fixture.safari])
        subject.coordinator.start()
        #expect(subject.presenter.renderedApps == [Fixture.safari])

        subject.apps.simulateChange(to: [Fixture.safari, Fixture.terminal])

        #expect(subject.presenter.renderedApps == [Fixture.safari, Fixture.terminal])
    }

    @Test("Unplugging every display tears down every surface — NFR-5")
    func allDisplaysRemoved() {
        let subject = makeSubject()
        subject.coordinator.start()
        #expect(subject.presenter.presentedDisplays.count == 2)

        subject.displays.simulateChange(to: [])

        #expect(subject.presenter.presentedDisplays.isEmpty)
    }

    @Test("A surviving display is repositioned, not rebuilt")
    func survivingDisplayRepositions() {
        let subject = makeSubject(displays: [Fixture.builtIn])
        subject.coordinator.start()

        subject.displays.simulateChange(to: [Fixture.builtIn, Fixture.external])

        // Tearing down and recreating a surviving panel would flicker.
        #expect(subject.presenter.repositioned.contains(Fixture.builtIn.id))
    }

    // MARK: - Configuration

    @Test("Stored configuration is loaded at init")
    func loadsStoredConfiguration() {
        var stored = DockConfiguration.default
        stored.edge = .left
        stored.iconSize = 64

        let subject = makeSubject(configuration: stored)

        #expect(subject.coordinator.configuration.edge == .left)
        #expect(subject.coordinator.configuration.iconSize == 64)
    }

    @Test("An empty store falls back to defaults — FR-4.2")
    func fallsBackToDefaults() {
        let subject = makeSubject(configuration: nil)

        // Every field defaults except the one seeded from the system Dock,
        // whose absent `show-recents` means on.
        var expected = DockConfiguration.default
        expected.showsRecentApps = true
        #expect(subject.coordinator.configuration == expected)
    }

    @Test("A first launch seeds pinned apps from the system Dock")
    func firstLaunchSeedsPinnedApps() {
        // Reported from use: the dock arrived empty, so every icon on it was an
        // already-running app and clicking one could only switch to it. Nothing
        // could be launched, which read as the dock being broken.
        let systemDock = FakeSystemDock(persistent: [Fixture.safari, Fixture.terminal])
        let subject = makeSubject(configuration: nil, systemDock: systemDock)

        #expect(
            subject.coordinator.configuration.pinnedItems.map(\.bundleIdentifier)
                == [Fixture.safari.bundleIdentifier, Fixture.terminal.bundleIdentifier])
    }

    @Test("A seeded dock shows apps that are not running")
    func seededDockShowsNotRunningApps() {
        // The point of seeding: something to click that is not already open.
        let systemDock = FakeSystemDock(persistent: [Fixture.safari])
        let subject = makeSubject(
            displays: [Fixture.builtIn], running: [], configuration: nil, systemDock: systemDock)

        subject.coordinator.start()

        #expect(subject.presenter.renderedApps == [Fixture.safari])
        #expect(subject.presenter.renderedElements.first?.entry?.isRunning == false)
    }

    @Test("A first launch adopts the system Dock's icon size")
    func firstLaunchSeedsIconSize() {
        let systemDock = FakeSystemDock(tileSize: 66)
        let subject = makeSubject(configuration: nil, systemDock: systemDock)

        #expect(subject.coordinator.configuration.iconSize == 66)
    }

    @Test("Deleted apps are not seeded")
    func firstLaunchSkipsDeletedApps() {
        // Apple's Dock keeps tiles for apps that have been removed, so a tile
        // is not evidence the app is still installed.
        let systemDock = FakeSystemDock(persistent: [Fixture.safari, Fixture.terminal])
        let catalog = FakeApplicationCatalog()
        catalog.missingPaths = [Fixture.terminal.path]

        let subject = makeSubject(configuration: nil, systemDock: systemDock, catalog: catalog)

        #expect(
            subject.coordinator.configuration.pinnedItems.map(\.bundleIdentifier)
                == [Fixture.safari.bundleIdentifier])
    }

    @Test("Stored settings are never overwritten by seeding")
    func storedConfigurationIsNotReseeded() {
        // Seed-then-diverge: an import on every launch would undo removals and
        // keep resurrecting apps the user took off their dock.
        var stored = DockConfiguration.default
        stored.pinnedItems = [DockItem(Fixture.preview)]

        let systemDock = FakeSystemDock(persistent: [Fixture.safari, Fixture.terminal])
        let subject = makeSubject(configuration: stored, systemDock: systemDock)

        #expect(
            subject.coordinator.configuration.pinnedItems.map(\.bundleIdentifier)
                == [Fixture.preview.bundleIdentifier])
    }

    @Test("Disabling a display persists and removes its surface")
    func disablingDisplayPersistsAndRefreshes() {
        let subject = makeSubject()
        subject.coordinator.start()

        subject.coordinator.setEnabled(false, for: Fixture.external.id)

        // Both halves matter: a setting that saves without refreshing looks
        // broken, and one that refreshes without saving forgets on relaunch.
        #expect(subject.store.saveCount == 1)
        #expect(subject.store.stored?.isEnabled(Fixture.external.id) == false)
        #expect(subject.presenter.presentedDisplays == [Fixture.builtIn.id])
    }

    @Test("Re-enabling a display restores its surface")
    func reenablingRestoresSurface() {
        let subject = makeSubject()
        subject.coordinator.start()
        subject.coordinator.setEnabled(false, for: Fixture.external.id)

        subject.coordinator.setEnabled(true, for: Fixture.external.id)

        #expect(subject.presenter.presentedDisplays.contains(Fixture.external.id))
    }

    @Test("Changing edge rebuilds every surface")
    func edgeChangeRebuilds() {
        let subject = makeSubject()
        subject.coordinator.start()

        subject.coordinator.setEdge(.left)

        // Orientation is fixed at construction, so surfaces must be rebuilt
        // rather than repositioned.
        #expect(subject.presenter.dismissAllCount == 1)
        #expect(subject.presenter.presentedDisplays.count == 2)
        #expect(subject.store.stored?.edge == .left)
    }

    @Test("Toggling running apps persists and re-renders")
    func showsRunningAppsToggle() {
        let subject = makeSubject(displays: [Fixture.builtIn], running: [Fixture.safari])
        subject.coordinator.start()

        subject.coordinator.setShowsRunningApps(false)

        #expect(subject.store.stored?.showsRunningApps == false)
        #expect(subject.presenter.renderedApps.isEmpty)
    }

    @Test("Turning off Dock avoidance reclaims that display")
    func avoidanceToggleReclaimsDisplay() {
        let subject = makeSubject(displays: [Fixture.builtInWithDock, Fixture.external])
        subject.coordinator.start()
        #expect(subject.presenter.presentedDisplays == [Fixture.external.id])

        subject.coordinator.setAvoidsSystemDockDisplay(false)

        #expect(subject.presenter.presentedDisplays.count == 2)
        #expect(subject.store.stored?.avoidsSystemDockDisplay == false)
    }

    // MARK: - Actions

    @Test("Clicking an icon activates it on the display that was clicked")
    func activatePassesDisplay() {
        let subject = makeSubject()
        subject.coordinator.start()

        subject.coordinator.activate(Fixture.safari, on: Fixture.external.id)

        #expect(subject.apps.activated.count == 1)
        #expect(subject.apps.activated.first?.app == Fixture.safari)
        // Without the display, the app opens wherever macOS chooses.
        #expect(subject.apps.activated.first?.display == Fixture.external.id)
    }

    @Test("Quit is forwarded to the system")
    func quitForwards() {
        let subject = makeSubject()
        subject.coordinator.quit(Fixture.safari)
        #expect(subject.apps.quit == [Fixture.safari])
    }

    @Test("Opening Trash is forwarded to the system")
    func trashForwards() {
        let subject = makeSubject()
        subject.coordinator.openTrash()
        #expect(subject.apps.trashOpenCount == 1)
    }

    @Test("Pinning persists and re-renders")
    func pinningPersists() {
        let subject = makeSubject(displays: [Fixture.builtIn], running: [Fixture.safari])
        subject.coordinator.start()
        #expect(!subject.coordinator.isPinned(Fixture.safari))

        subject.coordinator.togglePin(Fixture.safari)

        #expect(subject.coordinator.isPinned(Fixture.safari))
        #expect(subject.store.stored?.isPinned(Fixture.safari.bundleIdentifier) == true)
    }

    @Test("A pinned app survives quitting")
    func pinnedAppSurvivesQuit() {
        let subject = makeSubject(displays: [Fixture.builtIn], running: [Fixture.safari])
        subject.coordinator.start()
        subject.coordinator.togglePin(Fixture.safari)

        // Safari quits; the pin must keep it on the dock, now not running.
        subject.apps.simulateChange(to: [])

        #expect(subject.presenter.renderedApps == [Fixture.safari])
        #expect(subject.presenter.renderedElements.first?.entry?.isRunning == false)
    }

    @Test("Unpinning a stopped app removes it entirely")
    func unpinningStoppedAppRemovesIt() {
        let subject = makeSubject(displays: [Fixture.builtIn], running: [])
        subject.coordinator.start()
        subject.coordinator.togglePin(Fixture.safari)
        #expect(subject.presenter.renderedApps == [Fixture.safari])

        subject.coordinator.togglePin(Fixture.safari)

        #expect(subject.presenter.renderedApps.isEmpty)
    }

    // MARK: - Recents

    @Test("A first launch takes its recents setting from the system Dock — T8 Tier 2")
    func recentsPreferenceIsSeededFromSystemDock() {
        let subject = makeSubject(
            configuration: nil, systemDock: FakeSystemDock(showsRecentApplications: false))

        // Someone who turned recents off on the system Dock has already said
        // what they want; asking again by defaulting to on would ignore it.
        #expect(!subject.coordinator.configuration.showsRecentApps)
    }

    @Test("A stored setting outranks the system Dock's — seed, then diverge")
    func storedRecentsPreferenceWins() {
        var stored = DockConfiguration.default
        stored.showsRecentApps = false

        let subject = makeSubject(
            configuration: stored, systemDock: FakeSystemDock(showsRecentApplications: true))

        #expect(!subject.coordinator.configuration.showsRecentApps)
    }

    @Test("Recent apps are rendered in their own section")
    func recentsAreRendered() {
        var stored = DockConfiguration.default
        stored.showsRecentApps = true

        let subject = makeSubject(
            displays: [Fixture.builtIn],
            running: [Fixture.safari],
            configuration: stored,
            systemDock: FakeSystemDock(recents: [Fixture.preview])
        )
        subject.coordinator.start()

        #expect(subject.presenter.renderedApps == [Fixture.safari, Fixture.preview])
    }

    @Test("A recent app that has been deleted is not offered")
    func deletedRecentIsNotRendered() {
        var stored = DockConfiguration.default
        stored.showsRecentApps = true
        let catalog = FakeApplicationCatalog()
        catalog.missingPaths = [Fixture.preview.path]

        let subject = makeSubject(
            displays: [Fixture.builtIn],
            configuration: stored,
            systemDock: FakeSystemDock(recents: [Fixture.preview]),
            catalog: catalog
        )
        subject.coordinator.start()

        #expect(subject.presenter.renderedApps.isEmpty)
    }

    @Test("Recents are re-read on each refresh, not captured at launch")
    func recentsAreRereadOnRefresh() {
        // The Dock rewrites `recent-apps` as apps are used, so a list read
        // once at launch is stale by the time anybody looks at the dock.
        var stored = DockConfiguration.default
        stored.showsRecentApps = true

        let subject = makeSubject(
            displays: [Fixture.builtIn], configuration: stored, systemDock: FakeSystemDock())
        subject.coordinator.start()
        #expect(subject.presenter.renderedApps.isEmpty)

        subject.systemDock.setRecents([Fixture.preview])
        subject.apps.simulateChange(to: [])

        #expect(subject.presenter.renderedApps == [Fixture.preview])
    }

    @Test("Toggling recents persists and re-renders")
    func recentsToggle() {
        let subject = makeSubject(
            displays: [Fixture.builtIn],
            configuration: .default,
            systemDock: FakeSystemDock(recents: [Fixture.preview])
        )
        subject.coordinator.start()
        #expect(subject.presenter.renderedApps.isEmpty)

        subject.coordinator.setShowsRecentApps(true)

        #expect(subject.store.stored?.showsRecentApps == true)
        #expect(subject.presenter.renderedApps == [Fixture.preview])
    }

    // MARK: - Importing and browsing

    @Test("Importing pins the system Dock's apps in the order it holds them")
    func importPinsInDockOrder() {
        let subject = makeSubject(
            displays: [Fixture.builtIn],
            configuration: .default,
            systemDock: FakeSystemDock(persistent: [Fixture.terminal, Fixture.safari])
        )
        subject.coordinator.start()

        subject.coordinator.importFromSystemDock()

        #expect(subject.coordinator.configuration.pinnedItems.map(\.name) == ["Terminal", "Safari"])
        // Both halves: a setting that saves without refreshing looks broken.
        #expect(subject.store.stored?.pinnedItems.count == 2)
        #expect(subject.presenter.renderedApps == [Fixture.terminal, Fixture.safari])
    }

    @Test("Importing merges with existing pins rather than replacing them")
    func importMergesWithExistingPins() {
        // An import that wiped what the user had arranged here would be a
        // destructive action behind an innocuous menu item.
        var stored = DockConfiguration.default
        stored.pin(Fixture.preview)

        let subject = makeSubject(
            displays: [Fixture.builtIn],
            configuration: stored,
            systemDock: FakeSystemDock(persistent: [Fixture.safari])
        )
        subject.coordinator.start()

        subject.coordinator.importFromSystemDock()

        #expect(subject.coordinator.configuration.pinnedItems.map(\.name) == ["Preview", "Safari"])
    }

    @Test("Importing an app that is already pinned does not duplicate it")
    func importDoesNotDuplicatePins() {
        var stored = DockConfiguration.default
        stored.pin(Fixture.safari)

        let subject = makeSubject(
            displays: [Fixture.builtIn],
            configuration: stored,
            systemDock: FakeSystemDock(persistent: [Fixture.safari, Fixture.terminal])
        )
        subject.coordinator.start()

        subject.coordinator.importFromSystemDock()

        #expect(subject.coordinator.configuration.pinnedItems.map(\.name) == ["Safari", "Terminal"])
    }

    @Test("Importing skips apps the system Dock still lists but that are gone")
    func importSkipsUninstalledApps() {
        let catalog = FakeApplicationCatalog()
        catalog.missingPaths = [Fixture.terminal.path]

        let subject = makeSubject(
            displays: [Fixture.builtIn],
            configuration: .default,
            systemDock: FakeSystemDock(persistent: [Fixture.safari, Fixture.terminal]),
            catalog: catalog
        )
        subject.coordinator.start()

        subject.coordinator.importFromSystemDock()

        #expect(subject.coordinator.configuration.pinnedItems.map(\.name) == ["Safari"])
    }

    @Test("Importing an empty system Dock changes nothing")
    func importFromEmptyDockIsHarmless() {
        var stored = DockConfiguration.default
        stored.pin(Fixture.preview)

        let subject = makeSubject(
            displays: [Fixture.builtIn], configuration: stored, systemDock: FakeSystemDock())
        subject.coordinator.start()

        subject.coordinator.importFromSystemDock()

        #expect(subject.coordinator.configuration.pinnedItems.map(\.name) == ["Preview"])
    }

    @Test("Installed applications are offered for browsing, filed by initial")
    func installedApplicationsAreBrowsable() {
        let subject = makeSubject(
            catalog: FakeApplicationCatalog([Fixture.terminal, Fixture.safari]))

        let groups = subject.coordinator.installedApplicationGroups

        #expect(groups.map(\.title) == ["S", "T"])
        #expect(groups.first?.applications == [Fixture.safari])
    }

    @Test("An appearance change refreshes surfaces and contents")
    func appearanceRefresh() {
        let subject = makeSubject(displays: [Fixture.builtIn])
        subject.coordinator.start()

        subject.coordinator.refreshAppearance()

        #expect(subject.presenter.appearanceRefreshCount == 1)
    }
}

/// Keeps dock surfaces in step with the hardware, the running applications,
/// and the user's settings.
///
/// Deliberately thin. It decides nothing itself: `DisplayReconciler` decides
/// which surfaces should exist and `DockContentBuilder` decides what goes in
/// them. This type wires those decisions to the outside world.
///
/// Lives in the domain layer and imports no UI framework, so its wiring —
/// which callback triggers which refresh — is testable with fakes. That
/// wiring is where the display-follows-Dock bug lived while every pure-function
/// test passed.
@MainActor
public final class DockCoordinator {
    private let displayProvider: any DisplayProviding
    private let applicationProvider: any ApplicationProviding
    private let systemDock: any SystemDockReading
    private let applicationCatalog: any InstalledApplicationProviding
    private let store: any ConfigurationStoring
    private let presenter: any DockPresenting

    public private(set) var configuration: DockConfiguration

    public init(
        displayProvider: any DisplayProviding,
        applicationProvider: any ApplicationProviding,
        systemDock: any SystemDockReading,
        applicationCatalog: any InstalledApplicationProviding,
        store: any ConfigurationStoring,
        presenter: any DockPresenting
    ) {
        self.displayProvider = displayProvider
        self.applicationProvider = applicationProvider
        self.systemDock = systemDock
        self.applicationCatalog = applicationCatalog
        self.store = store
        self.presenter = presenter

        // FR-4.2: unreadable or absent settings must still yield a usable app.
        if let stored = store.load() {
            self.configuration = stored
        } else {
            // Nothing stored means a first launch, so the settings the user
            // already made on the system Dock are the best guess available —
            // better than an arbitrary default. Seed-then-diverge: from the
            // first save onwards, ours wins. (T8 Tier 2.)
            var seeded = DockConfiguration.default
            seeded.showsRecentApps = SystemDockPreferences.showsRecentApplications(
                systemDock.showsRecentApplications)

            // Pinned apps are seeded too, not just the preferences. An empty
            // dock on first launch shows nothing but whatever happens to be
            // running, so every icon is an app the user could already reach and
            // clicking one can only ever switch to it — the dock looks broken
            // precisely because it cannot launch anything. Importing here is
            // also what the dock was asked to be: a second copy of the one they
            // already have. Still a seed rather than a mirror, so anything they
            // pin or remove afterwards is theirs and survives.
            seeded.pinnedItems = SystemDockPreferences.applications(
                fromTiles: systemDock.persistentApplicationTiles,
                isInstalled: applicationCatalog.applicationExists(atPath:)
            ).map(DockItem.init)

            self.configuration = seeded
        }
    }

    public func start() {
        displayProvider.onDisplayChange { [weak self] in
            self?.refreshDisplays()
        }
        applicationProvider.onRunningApplicationsChange { [weak self] in
            self?.refreshContents()
        }
        refreshDisplays()
    }

    // MARK: - Displays

    /// Brings surfaces in line with the currently connected, enabled displays.
    public func refreshDisplays() {
        let connected = displayProvider.connectedDisplays
        let plan = DisplayReconciler.plan(
            connected: connected,
            existingPanels: presenter.presentedDisplays,
            configuration: configuration
        )

        if !plan.isEmpty {
            apply(plan, connected: connected)
        }
        refreshContents()
    }

    private func apply(_ plan: ReconciliationPlan, connected: [DisplayInfo]) {
        for id in plan.toRemove {
            presenter.dismiss(id)
        }
        for id in plan.toCreate {
            guard let info = connected.first(where: { $0.id == id }) else { continue }
            presenter.present(on: info, configuration: configuration)
        }
        // Resolution or arrangement may have changed under a surviving surface.
        for id in plan.toUpdate {
            presenter.reposition(id)
        }
    }

    // MARK: - Contents

    /// Recomputes what every surface shows.
    ///
    /// Every surface shows the same contents, so the list is built once and
    /// rendered everywhere — not rebuilt per display.
    public func refreshContents() {
        presenter.render(
            DockContentBuilder.elements(
                pinned: configuration.pinnedItems,
                running: applicationProvider.runningApplications,
                recents: recentApplications(),
                showsRunningApps: configuration.showsRunningApps,
                showsRecentApps: configuration.showsRecentApps
            )
        )
    }

    /// Re-read on every refresh rather than cached at launch.
    ///
    /// The Dock rewrites `recent-apps` as applications are used, so a list
    /// captured once is stale by the time anyone looks at it. This is a
    /// defaults lookup, not a file watch — the alternative, watching the plist
    /// as ExtraDock does, costs a file descriptor and rules out sandboxing.
    private func recentApplications() -> [ApplicationInfo] {
        guard configuration.showsRecentApps else { return [] }

        return SystemDockPreferences.applications(
            fromTiles: systemDock.recentApplicationTiles,
            isInstalled: applicationCatalog.applicationExists(atPath:)
        )
    }

    /// Rebuilds surface chrome after an accessibility or appearance change.
    public func refreshAppearance() {
        presenter.refreshAppearance()
        refreshContents()
    }

    // MARK: - Browsing and importing

    /// Every installed application, filed by initial for a browser menu.
    ///
    /// Read on demand so an application installed while fruit-dock is running
    /// still appears.
    public var installedApplicationGroups: [ApplicationGroup] {
        ApplicationCatalog.groups(from: applicationCatalog.installedApplications)
    }

    /// Merges the system Dock's pinned applications into ours. FR-3.1.
    ///
    /// A one-off action rather than a live sync. Continuous mirroring would
    /// make the two docks the same dock, which defeats the point of a second
    /// one, and would silently undo any arrangement the user made here.
    /// Merging rather than replacing is the same argument: what they already
    /// pinned is theirs, and an import must never be able to lose it.
    public func importFromSystemDock() {
        let imported = SystemDockPreferences.applications(
            fromTiles: systemDock.persistentApplicationTiles,
            isInstalled: applicationCatalog.applicationExists(atPath:)
        )
        // `pin` is a no-op for anything already pinned, so existing items keep
        // both their place and their order.
        for application in imported {
            configuration.pin(application)
        }

        store.save(configuration)
        refreshContents()
    }

    // MARK: - Settings

    public func setEnabled(_ enabled: Bool, for display: DisplayID) {
        configuration.setEnabled(enabled, for: display)
        store.save(configuration)
        refreshDisplays()
    }

    public func setEdge(_ edge: DockEdge) {
        configuration.edge = edge
        store.save(configuration)
        // Orientation is fixed when a surface is built, so an edge change
        // needs new surfaces rather than a reposition.
        presenter.dismissAll()
        refreshDisplays()
    }

    public func setShowsRunningApps(_ shows: Bool) {
        configuration.showsRunningApps = shows
        store.save(configuration)
        refreshContents()
    }

    public func setShowsRecentApps(_ shows: Bool) {
        configuration.showsRecentApps = shows
        store.save(configuration)
        refreshContents()
    }

    public func setAvoidsSystemDockDisplay(_ avoids: Bool) {
        configuration.avoidsSystemDockDisplay = avoids
        store.save(configuration)
        // Changes which displays qualify, so this is a display-level refresh.
        refreshDisplays()
    }
}

// MARK: - DockActionHandling

extension DockCoordinator: DockActionHandling {
    public func activate(_ application: ApplicationInfo, on displayID: DisplayID?) {
        applicationProvider.activateOrLaunch(application, on: displayID)
    }

    public func quit(_ application: ApplicationInfo) {
        applicationProvider.quit(application)
    }

    public func togglePin(_ application: ApplicationInfo) {
        if configuration.isPinned(application.bundleIdentifier) {
            configuration.unpin(application.bundleIdentifier)
        } else {
            configuration.pin(application)
        }
        store.save(configuration)
        refreshContents()
    }

    public func isPinned(_ application: ApplicationInfo) -> Bool {
        configuration.isPinned(application.bundleIdentifier)
    }

    public func openTrash() {
        applicationProvider.openTrash()
    }
}

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
    private let store: any ConfigurationStoring
    private let presenter: any DockPresenting

    public private(set) var configuration: DockConfiguration

    public init(
        displayProvider: any DisplayProviding,
        applicationProvider: any ApplicationProviding,
        store: any ConfigurationStoring,
        presenter: any DockPresenting
    ) {
        self.displayProvider = displayProvider
        self.applicationProvider = applicationProvider
        self.store = store
        self.presenter = presenter
        // FR-4.2: unreadable or absent settings must still yield a usable app.
        self.configuration = store.load() ?? .default
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
                showsRunningApps: configuration.showsRunningApps
            )
        )
    }

    /// Rebuilds surface chrome after an accessibility or appearance change.
    public func refreshAppearance() {
        presenter.refreshAppearance()
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

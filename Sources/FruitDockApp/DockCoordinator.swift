import AppKit
import FruitDockCore

/// Owns the live dock panels and keeps them in step with the hardware, the
/// running applications, and the user's system settings.
///
/// Deliberately thin. It decides nothing: `DisplayReconciler` decides which
/// panels should exist and `DockContentBuilder` decides what goes in them.
/// This type only carries those decisions out.
@MainActor
final class DockCoordinator {
    private let displayProvider: any DisplayProviding
    private let applicationProvider: any ApplicationProviding
    private let store: any ConfigurationStoring

    private var panels: [DisplayID: DockPanel] = [:]
    private var appearanceObserver: NSObjectProtocol?
    private(set) var configuration: DockConfiguration

    init(
        displayProvider: any DisplayProviding,
        applicationProvider: any ApplicationProviding,
        store: any ConfigurationStoring
    ) {
        self.displayProvider = displayProvider
        self.applicationProvider = applicationProvider
        self.store = store
        // FR-4.2: unreadable or absent settings must still yield a usable app.
        self.configuration = store.load() ?? .default
    }

    func start() {
        displayProvider.onDisplayChange { [weak self] in
            self?.refreshDisplays()
        }
        applicationProvider.onRunningApplicationsChange { [weak self] in
            self?.refreshContents()
        }
        // Reduce Transparency and friends can be toggled while running; a dock
        // that only reads them at launch is a dock that ignores them.
        appearanceObserver = SystemAppearance.observeChanges { [weak self] in
            self?.refreshAppearance()
        }
        refreshDisplays()
    }

    // MARK: - Displays

    /// Brings panels in line with the currently connected, enabled displays.
    func refreshDisplays() {
        let connected = displayProvider.connectedDisplays
        let plan = DisplayReconciler.plan(
            connected: connected,
            existingPanels: Set(panels.keys),
            configuration: configuration
        )

        if !plan.isEmpty {
            apply(plan, connected: connected)
        }
        refreshContents()
    }

    private func apply(_ plan: ReconciliationPlan, connected: [DisplayInfo]) {
        for id in plan.toRemove {
            // Detached from the dictionary first so a panel mid-fade is never
            // mistaken for a live one if displays change again during it.
            panels.removeValue(forKey: id)?.fadeOutAndClose()
        }

        for id in plan.toCreate {
            guard
                let info = connected.first(where: { $0.id == id }),
                let screen = SystemDisplayProvider.screen(for: id)
            else { continue }

            panels[id] = DockPanel(display: info, screen: screen, configuration: configuration)
        }

        // Resolution or arrangement may have changed under a surviving panel.
        for id in plan.toUpdate {
            panels[id]?.updatePosition()
        }
    }

    // MARK: - Contents

    /// Recomputes what every panel shows.
    ///
    /// Every panel shows the same contents, so the list is built once and
    /// handed to each — not rebuilt per display.
    private func refreshContents() {
        let elements = DockContentBuilder.elements(
            pinned: configuration.pinnedItems,
            running: applicationProvider.runningApplications,
            showsRunningApps: configuration.showsRunningApps
        )
        let handlers = makeHandlers()

        for panel in panels.values {
            panel.update(elements: elements, handlers: handlers)
            // Newly created panels start transparent so they never flash at
            // the wrong size; revealing here means contents are already set.
            panel.fadeIn()
        }
    }

    private func makeHandlers() -> DockBarHandlers {
        DockBarHandlers(
            activate: { [weak self] app in self?.applicationProvider.activateOrLaunch(app) },
            quit: { [weak self] app in self?.applicationProvider.quit(app) },
            togglePin: { [weak self] app in self?.togglePin(app) },
            isPinned: { [weak self] app in
                self?.configuration.isPinned(app.bundleIdentifier) ?? false
            },
            openTrash: {
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: (NSHomeDirectory() as NSString)
                        .appendingPathComponent(".Trash"))
                )
            }
        )
    }

    private func refreshAppearance() {
        for panel in panels.values {
            panel.refreshAppearance()
        }
        refreshContents()
    }

    // MARK: - Settings

    func setEnabled(_ enabled: Bool, for display: DisplayID) {
        configuration.setEnabled(enabled, for: display)
        persistAndRefreshDisplays()
    }

    func setEdge(_ edge: DockEdge) {
        configuration.edge = edge
        store.save(configuration)
        // Orientation is fixed when a panel is built, so an edge change needs
        // new panels rather than a reposition.
        rebuildAllPanels()
    }

    func setShowsRunningApps(_ shows: Bool) {
        configuration.showsRunningApps = shows
        store.save(configuration)
        refreshContents()
    }

    func setAvoidsSystemDockDisplay(_ avoids: Bool) {
        configuration.avoidsSystemDockDisplay = avoids
        // Changes which displays qualify, so this is a display-level refresh.
        persistAndRefreshDisplays()
    }

    private func togglePin(_ application: ApplicationInfo) {
        if configuration.isPinned(application.bundleIdentifier) {
            configuration.unpin(application.bundleIdentifier)
        } else {
            configuration.pin(application)
        }
        store.save(configuration)
        refreshContents()
    }

    private func persistAndRefreshDisplays() {
        store.save(configuration)
        refreshDisplays()
    }

    private func rebuildAllPanels() {
        for panel in panels.values { panel.fadeOutAndClose() }
        panels.removeAll()
        refreshDisplays()
    }
}

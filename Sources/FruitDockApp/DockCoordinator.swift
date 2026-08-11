import AppKit
import FruitDockCore

/// Owns the live dock panels and keeps them in step with the hardware.
///
/// Deliberately thin. It decides nothing — `DisplayReconciler` produces a
/// plan, and this type carries it out. Keeping the judgement in a pure
/// function is what makes the display-change paths testable.
@MainActor
final class DockCoordinator {
    private let displayProvider: any DisplayProviding
    private let store: any ConfigurationStoring

    private var panels: [DisplayID: DockPanel] = [:]
    private(set) var configuration: DockConfiguration

    init(displayProvider: any DisplayProviding, store: any ConfigurationStoring) {
        self.displayProvider = displayProvider
        self.store = store
        // FR-4.2: unreadable or absent settings must still yield a usable app.
        self.configuration = store.load() ?? .default
    }

    func start() {
        displayProvider.onDisplayChange { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    /// Brings panels in line with the currently connected, enabled displays.
    func refresh() {
        let connected = displayProvider.connectedDisplays
        let plan = DisplayReconciler.plan(
            connected: connected,
            existingPanels: Set(panels.keys),
            configuration: configuration
        )

        guard !plan.isEmpty else { return }
        apply(plan, connected: connected)
    }

    private func apply(_ plan: ReconciliationPlan, connected: [DisplayInfo]) {
        for id in plan.toRemove {
            panels.removeValue(forKey: id)?.close()
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

    // MARK: - Settings

    func setEnabled(_ enabled: Bool, for display: DisplayID) {
        configuration.setEnabled(enabled, for: display)
        store.save(configuration)
        refresh()
    }

    func setEdge(_ edge: DockEdge) {
        configuration.edge = edge
        store.save(configuration)
        rebuildAllPanels()
    }

    /// Tears down and recreates every panel.
    ///
    /// Used for changes a live panel cannot absorb, such as moving to a
    /// different edge. Cruder than mutating in place, but the panel count is
    /// small and correctness is easier to see.
    private func rebuildAllPanels() {
        for (_, panel) in panels { panel.close() }
        panels.removeAll()
        refresh()
    }

    var activeDisplayIDs: Set<DisplayID> { Set(panels.keys) }
}

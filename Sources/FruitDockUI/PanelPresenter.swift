import AppKit
import FruitDockCore

/// Turns the coordinator's decisions into real windows.
///
/// The only owner of `DockPanel` instances. Isolating window creation here is
/// what lets `DockCoordinator` be tested without opening windows.
@MainActor
final class PanelPresenter: DockPresenting {
    weak var actionHandler: (any DockActionHandling)?

    private var panels: [DisplayID: DockPanel] = [:]
    private var lastElements: [DockElement] = []

    /// What each panel was built from, so a panel can be rebuilt without the
    /// coordinator having to describe it again. `reposition` is told only which
    /// display moved, and rebuilding needs more than that.
    private var displays: [DisplayID: DisplayInfo] = [:]
    private var configuration: DockConfiguration = .default

    var presentedDisplays: Set<DisplayID> { Set(panels.keys) }

    func present(on display: DisplayInfo, configuration: DockConfiguration) {
        // A display can vanish between the plan being made and carried out.
        // Skipping leaves it absent from `presentedDisplays`, so the next
        // reconciliation simply tries again.
        guard let screen = SystemDisplayProvider.screen(for: display.id) else { return }

        self.displays[display.id] = display
        self.configuration = configuration

        let panel = DockPanel(display: display, screen: screen, configuration: configuration)
        panel.actionHandler = actionHandler
        panels[display.id] = panel

        // A surface created mid-session has missed the last render.
        if !lastElements.isEmpty {
            panel.update(elements: lastElements)
            panel.fadeIn()
        }
    }

    func dismiss(_ displayID: DisplayID) {
        // Detached from the dictionary before fading, so a surface mid-fade is
        // never mistaken for a live one if displays change again during it.
        panels.removeValue(forKey: displayID)?.fadeOutAndClose()
    }

    func dismissAll() {
        for panel in panels.values { panel.fadeOutAndClose() }
        panels.removeAll()
    }

    func reposition(_ displayID: DisplayID) {
        guard let panel = panels[displayID] else { return }

        // A resolution change arrives here as a reposition, but icon size is
        // derived from the display's height and fixed when the panel is built.
        // Moving it alone would leave a dock scaled for the resolution the
        // display no longer has.
        if panel.isStale(for: configuration), let display = displays[displayID] {
            rebuild(display)
            return
        }

        panel.updatePosition()
    }

    /// Replaces a panel in place, keeping its contents.
    ///
    /// Closed without fading: a fade would cross with the replacement's fade-in
    /// and read as a flicker, where an instant swap reads as a resize.
    private func rebuild(_ display: DisplayInfo) {
        panels.removeValue(forKey: display.id)?.close()
        present(on: display, configuration: configuration)
    }

    func render(_ elements: [DockElement]) {
        lastElements = elements
        for panel in panels.values {
            panel.update(elements: elements)
            // Panels are created transparent so they never flash at the wrong
            // size; revealing here means contents and frame are already set.
            panel.fadeIn()
        }
    }

    func refreshAppearance() {
        for panel in panels.values { panel.refreshAppearance() }
    }
}

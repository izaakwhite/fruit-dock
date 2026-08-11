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

    var presentedDisplays: Set<DisplayID> { Set(panels.keys) }

    func present(on display: DisplayInfo, configuration: DockConfiguration) {
        // A display can vanish between the plan being made and carried out.
        // Skipping leaves it absent from `presentedDisplays`, so the next
        // reconciliation simply tries again.
        guard let screen = SystemDisplayProvider.screen(for: display.id) else { return }

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
        panels[displayID]?.updatePosition()
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

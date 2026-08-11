import AppKit
import FruitDockCore

/// Composition root.
///
/// The one place that constructs concrete system-backed types and wires them
/// together. Everything downstream receives its dependencies, so nothing else
/// needs to reach for global state.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: DockCoordinator!
    private var statusItem: NSStatusItem!
    private let displayProvider = SystemDisplayProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = DockCoordinator(
            displayProvider: displayProvider,
            applicationProvider: SystemApplicationProvider(),
            store: UserDefaultsConfigurationStore()
        )

        setUpStatusItem()
        coordinator.start()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "dock.rectangle",
            accessibilityDescription: "fruit-dock"
        )

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Rebuilt on each open so the display list is never stale.
    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(.sectionHeader(title: "Show dock on"))

        for display in displayProvider.connectedDisplays {
            let item = NSMenuItem(
                title: display.name,
                action: #selector(toggleDisplay(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = display.id
            item.state = coordinator.configuration.isEnabled(display.id) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let edgeItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let edgeMenu = NSMenu()
        for edge in DockEdge.allCases {
            let item = NSMenuItem(
                title: edge.rawValue.capitalized,
                action: #selector(selectEdge(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = edge
            item.state = coordinator.configuration.edge == edge ? .on : .off
            edgeMenu.addItem(item)
        }
        edgeItem.submenu = edgeMenu
        menu.addItem(edgeItem)

        let runningItem = NSMenuItem(
            title: "Show Running Apps",
            action: #selector(toggleShowsRunningApps(_:)),
            keyEquivalent: ""
        )
        runningItem.target = self
        runningItem.state = coordinator.configuration.showsRunningApps ? .on : .off
        menu.addItem(runningItem)

        let avoidItem = NSMenuItem(
            title: "Skip Display with macOS Dock",
            action: #selector(toggleAvoidsSystemDock(_:)),
            keyEquivalent: ""
        )
        avoidItem.target = self
        avoidItem.state = coordinator.configuration.avoidsSystemDockDisplay ? .on : .off
        menu.addItem(avoidItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit fruit-dock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
    }

    @objc private func toggleDisplay(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? DisplayID else { return }
        coordinator.setEnabled(sender.state == .off, for: id)
    }

    @objc private func selectEdge(_ sender: NSMenuItem) {
        guard let edge = sender.representedObject as? DockEdge else { return }
        coordinator.setEdge(edge)
    }

    @objc private func toggleShowsRunningApps(_ sender: NSMenuItem) {
        coordinator.setShowsRunningApps(sender.state == .off)
    }

    @objc private func toggleAvoidsSystemDock(_ sender: NSMenuItem) {
        coordinator.setAvoidsSystemDockDisplay(sender.state == .off)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}

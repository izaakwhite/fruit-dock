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
    private var appearanceObserver: NSObjectProtocol?

    private let displayProvider = SystemDisplayProvider()
    private let presenter = PanelPresenter()
    private let accessibility = AccessibilityPermission()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = DockCoordinator(
            displayProvider: displayProvider,
            applicationProvider: SystemApplicationProvider(accessibility: accessibility),
            store: UserDefaultsConfigurationStore(),
            presenter: presenter
        )
        // Weak on the presenter's side; the coordinator owns the relationship.
        presenter.actionHandler = coordinator

        // Reduce Transparency and friends can be toggled while running; a dock
        // that only reads them at launch is a dock that ignores them.
        appearanceObserver = SystemAppearance.observeChanges { [weak coordinator] in
            coordinator?.refreshAppearance()
        }

        setUpStatusItem()
        coordinator.start()

        // Only worth asking on a multi-display Mac. Opening apps on the
        // display you clicked is the only thing this permission buys, and with
        // one display there is nowhere else for them to open — a prompt then
        // is pure nag for a feature the user cannot use. The first placement
        // attempt asks instead if a second display arrives later.
        if displayProvider.connectedDisplays.count > 1 {
            accessibility.consider(.launch)
        }
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
                title: display.name, action: #selector(toggleDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = display.id
            item.state = coordinator.configuration.isEnabled(display.id) ? .on : .off
            // A display hosting Apple's Dock is skipped regardless, so showing
            // it as togglable would be a lie.
            item.isEnabled = !(display.hostsSystemDock
                && coordinator.configuration.avoidsSystemDockDisplay)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let edgeItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let edgeMenu = NSMenu()
        for edge in DockEdge.allCases {
            let item = NSMenuItem(
                title: edge.rawValue.capitalized, action: #selector(selectEdge(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = edge
            item.state = coordinator.configuration.edge == edge ? .on : .off
            edgeMenu.addItem(item)
        }
        edgeItem.submenu = edgeMenu
        menu.addItem(edgeItem)

        addToggle(
            to: menu,
            title: "Show Running Apps",
            isOn: coordinator.configuration.showsRunningApps,
            action: #selector(toggleShowsRunningApps(_:))
        )
        addToggle(
            to: menu,
            title: "Skip Display with macOS Dock",
            isOn: coordinator.configuration.avoidsSystemDockDisplay,
            action: #selector(toggleAvoidsSystemDock(_:))
        )

        menu.addItem(.separator())
        addAccessibilityItem(to: menu)

        menu.addItem(.separator())

        // One click to each pane people actually need. macOS will not let an
        // app change these itself, so landing them on the right screen is the
        // most that can be done — and is what Mac users expect.
        let settingsItem = NSMenuItem(title: "System Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        for (title, pane) in [
            ("Dock & Menu Bar…", SystemSettings.Pane.dock),
            ("Displays…", .displays),
            ("Accessibility: Display…", .accessibilityDisplay),
            ("Privacy: Accessibility…", .accessibilityPrivacy),
        ] {
            let item = NSMenuItem(
                title: title, action: #selector(openSettingsPane(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pane
            settingsMenu.addItem(item)
        }
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit fruit-dock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
    }

    /// Reports whether apps will actually open on the display that was clicked.
    ///
    /// Without Accessibility permission that half of the click silently does
    /// nothing — the app still activates, just wherever macOS decided — and a
    /// feature that fails invisibly reads as a broken app rather than an
    /// ungranted permission. Rebuilt with the rest of the menu on every open,
    /// so granting permission in System Settings is reflected without a
    /// relaunch and without anything to observe.
    ///
    /// Worded as the consequence rather than the permission: what the user
    /// noticed was the app opening on the wrong screen, not a missing entry in
    /// a privacy list.
    private func addAccessibilityItem(to menu: NSMenu) {
        let granted = accessibility.isGranted
        let item = NSMenuItem(
            title: granted
                ? "Opening Apps on the Clicked Display"
                : "Enable Opening Apps on the Clicked Display…",
            action: granted ? nil : #selector(grantAccessibility(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.state = granted ? .on : .off
        item.toolTip = granted
            ? "fruit-dock has Accessibility access and can move a window to the display you clicked."
            : "Without Accessibility access apps still open — macOS just chooses the display."
        menu.addItem(item)
    }

    private func addToggle(to menu: NSMenu, title: String, isOn: Bool, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        menu.addItem(item)
    }

    // MARK: - Actions

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

    @objc private func grantAccessibility(_ sender: NSMenuItem) {
        accessibility.requestFromMenu()
    }

    @objc private func openSettingsPane(_ sender: NSMenuItem) {
        guard let pane = sender.representedObject as? SystemSettings.Pane else { return }
        SystemSettings.open(pane)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}

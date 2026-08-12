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

    /// Created on first use rather than at launch — most sessions never open
    /// it, and it needs `coordinator` to already exist.
    private var preferencesWindowController: PreferencesWindowController?

    /// Populated only when it is about to open, so the filesystem scan behind
    /// it is not charged to every click of the status item — the menu people
    /// open to toggle a display should not wait on a directory listing.
    private let applicationsMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = DockCoordinator(
            displayProvider: displayProvider,
            applicationProvider: SystemApplicationProvider(accessibility: accessibility),
            systemDock: SystemDockDefaultsReader(),
            applicationCatalog: InstalledApplicationScanner(),
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
        applicationsMenu.delegate = self
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
            title: "Show Recent Apps",
            isOn: coordinator.configuration.showsRecentApps,
            action: #selector(toggleShowsRecentApps(_:))
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

        let browseItem = NSMenuItem(title: "Applications", action: nil, keyEquivalent: "")
        browseItem.submenu = applicationsMenu
        menu.addItem(browseItem)

        let importItem = NSMenuItem(
            title: "Import from macOS Dock", action: #selector(importFromSystemDock), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

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
        let preferencesItem = NSMenuItem(
            title: "fruit-dock Settings…", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit fruit-dock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
    }

    /// Every installed application, filed by initial.
    ///
    /// Menus rather than a Launchpad-style grid: a grid is a second window to
    /// place, dismiss, and keep from stealing focus, and it would duplicate
    /// Launchpad, which Dock.app already owns and which cannot be replaced.
    private func rebuildApplicationsMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        for group in coordinator.installedApplicationGroups {
            let groupItem = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            let groupMenu = NSMenu()

            for application in group.applications {
                let item = NSMenuItem(
                    title: application.name, action: #selector(openApplication(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = application
                item.image = Self.menuIcon(for: application)
                groupMenu.addItem(item)
            }

            groupItem.submenu = groupMenu
            menu.addItem(groupItem)
        }

        if menu.items.isEmpty {
            menu.addItem(.sectionHeader(title: "No applications found"))
        }
    }

    /// Menu-sized rather than full-sized: `NSWorkspace` hands back a 512pt
    /// icon, which AppKit would scale into a row three times its natural
    /// height.
    private static func menuIcon(for application: ApplicationInfo) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: application.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
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

    @objc private func toggleShowsRecentApps(_ sender: NSMenuItem) {
        coordinator.setShowsRecentApps(sender.state == .off)
    }

    @objc private func toggleAvoidsSystemDock(_ sender: NSMenuItem) {
        coordinator.setAvoidsSystemDockDisplay(sender.state == .off)
    }

    @objc private func importFromSystemDock() {
        coordinator.importFromSystemDock()
    }

    /// Opens on whichever display macOS chooses: the menu bar is not a dock,
    /// so there is no screen the user can be said to have asked for.
    @objc private func openApplication(_ sender: NSMenuItem) {
        guard let application = sender.representedObject as? ApplicationInfo else { return }
        coordinator.activate(application, on: nil)
    }

    @objc private func grantAccessibility(_ sender: NSMenuItem) {
        accessibility.requestFromMenu()
    }

    @objc private func openSettingsPane(_ sender: NSMenuItem) {
        guard let pane = sender.representedObject as? SystemSettings.Pane else { return }
        SystemSettings.open(pane)
    }

    /// Opens the Coexist/Replace settings window — the same choice as the
    /// "Skip Display with macOS Dock" menu checkbox above, in a dedicated
    /// window for people who want the fuller explanation. Both read and
    /// write `coordinator.configuration.avoidsSystemDockDisplay` through the
    /// same `setAvoidsSystemDockDisplay(_:)` call, so neither can drift from
    /// the other.
    @objc private func showPreferences() {
        let controller = preferencesWindowController ?? {
            let controller = PreferencesWindowController()
            controller.currentRelationship = { [weak self] in
                SystemDockRelationship(
                    avoidsSystemDockDisplay: self?.coordinator.configuration.avoidsSystemDockDisplay ?? true)
            }
            controller.setRelationship = { [weak self] relationship in
                self?.coordinator.setAvoidsSystemDockDisplay(relationship.avoidsSystemDockDisplay)
            }
            preferencesWindowController = controller
            return controller
        }()
        controller.present()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // The applications submenu is its own delegate callback so its scan of
        // the filesystem happens when it opens, not when the status item does.
        if menu === applicationsMenu {
            rebuildApplicationsMenu(menu)
        } else {
            rebuildMenu(menu)
        }
    }
}

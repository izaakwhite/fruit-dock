import Foundation
@testable import FruitDockCore

/// Test doubles for the four system collaborators.
///
/// These exist so the coordinator's *wiring* can be tested — which callback
/// triggers which refresh. That wiring is where a completely non-functional
/// feature once shipped with every pure-function test passing.

@MainActor
final class FakeDisplayProvider: DisplayProviding {
    var connectedDisplays: [DisplayInfo]
    private var handler: (() -> Void)?

    /// Whether anyone actually subscribed. A coordinator that never registers
    /// can never react, which is exactly how the real bug went unnoticed.
    var isObserved: Bool { handler != nil }

    init(_ displays: [DisplayInfo] = []) {
        self.connectedDisplays = displays
    }

    func onDisplayChange(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    /// Simulates the system reporting new display state.
    func simulateChange(to displays: [DisplayInfo]) {
        connectedDisplays = displays
        handler?()
    }
}

@MainActor
final class FakeApplicationProvider: ApplicationProviding {
    var runningApplications: [ApplicationInfo]
    private var handler: (() -> Void)?

    private(set) var activated: [(app: ApplicationInfo, display: DisplayID?)] = []
    private(set) var quit: [ApplicationInfo] = []
    private(set) var trashOpenCount = 0

    var isObserved: Bool { handler != nil }

    init(_ running: [ApplicationInfo] = []) {
        self.runningApplications = running
    }

    func onRunningApplicationsChange(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func simulateChange(to running: [ApplicationInfo]) {
        runningApplications = running
        handler?()
    }

    func activateOrLaunch(_ application: ApplicationInfo, on displayID: DisplayID?) {
        activated.append((application, displayID))
    }

    func quit(_ application: ApplicationInfo) {
        quit.append(application)
    }

    func openTrash() {
        trashOpenCount += 1
    }

    var minimizedWindows: [WindowTile] = []
    private(set) var openedFolders: [String] = []
    private(set) var restored: [WindowTile] = []

    func open(folderAtPath path: String) {
        openedFolders.append(path)
    }

    func restore(_ window: WindowTile) {
        restored.append(window)
        // The real provider's window leaves the dock once restored, and the
        // coordinator re-reads afterwards; the fake has to do the same or the
        // tile appears to survive its own click.
        minimizedWindows.removeAll { $0.id == window.id }
    }
}

/// Stands in for Apple's Dock's defaults domain.
///
/// Holds raw tiles rather than applications, exactly as the real reader does,
/// so the coordinator's tests exercise the parsing the app will actually run.
@MainActor
final class FakeSystemDock: SystemDockReading {
    var persistentApplicationTiles: [Any]
    var recentApplicationTiles: [Any]
    var persistentOtherTiles: [Any] = []
    var showsRecentApplications: Bool?
    var largeTileSize: Double?
    var magnificationEnabled = false

    /// nil is the common case, not an edge one: the key is absent on any Mac
    /// whose Dock size was never changed.
    var tileSize: Double?

    init(
        persistent: [ApplicationInfo] = [],
        recents: [ApplicationInfo] = [],
        folders: [DockFolder] = [],
        showsRecentApplications: Bool? = nil,
        tileSize: Double? = nil,
        largeTileSize: Double? = nil,
        magnificationEnabled: Bool = false
    ) {
        self.persistentApplicationTiles = persistent.map(Fixture.tile)
        self.recentApplicationTiles = recents.map(Fixture.tile)
        self.persistentOtherTiles = folders.map(Fixture.directoryTile)
        self.showsRecentApplications = showsRecentApplications
        self.tileSize = tileSize
        self.largeTileSize = largeTileSize
        self.magnificationEnabled = magnificationEnabled
    }

    /// Simulates the Dock rewriting `recent-apps`, which it does as apps are
    /// used rather than on any schedule of ours.
    func setRecents(_ applications: [ApplicationInfo]) {
        recentApplicationTiles = applications.map(Fixture.tile)
    }
}

@MainActor
final class FakeApplicationCatalog: InstalledApplicationProviding {
    var installedApplications: [ApplicationInfo]

    /// Paths reported as gone. Apple's Dock keeps tiles for apps that have
    /// been deleted, so this is the normal case, not an exotic one.
    var missingPaths: Set<String> = []

    init(_ installed: [ApplicationInfo] = []) {
        self.installedApplications = installed
    }

    func applicationExists(atPath path: String) -> Bool {
        !missingPaths.contains(path)
    }
}

@MainActor
final class FakeConfigurationStore: ConfigurationStoring {
    var stored: DockConfiguration?
    private(set) var saveCount = 0

    init(_ stored: DockConfiguration? = nil) {
        self.stored = stored
    }

    func load() -> DockConfiguration? { stored }

    func save(_ configuration: DockConfiguration) {
        stored = configuration
        saveCount += 1
    }
}

/// Records what would have been drawn, without drawing anything.
@MainActor
final class FakePresenter: DockPresenting {
    private(set) var presentedDisplays: Set<DisplayID> = []
    private(set) var renderedElements: [DockElement] = []
    private(set) var renderCount = 0
    private(set) var repositioned: [DisplayID] = []
    private(set) var dismissAllCount = 0
    private(set) var appearanceRefreshCount = 0

    func present(on display: DisplayInfo, configuration: DockConfiguration) {
        presentedDisplays.insert(display.id)
    }

    func dismiss(_ displayID: DisplayID) {
        presentedDisplays.remove(displayID)
    }

    func dismissAll() {
        presentedDisplays.removeAll()
        dismissAllCount += 1
    }

    func reposition(_ displayID: DisplayID) {
        repositioned.append(displayID)
    }

    func render(_ elements: [DockElement]) {
        renderedElements = elements
        renderCount += 1
    }

    func refreshAppearance() {
        appearanceRefreshCount += 1
    }

    /// Applications currently rendered, in order — the assertion most tests want.
    var renderedApps: [ApplicationInfo] {
        renderedElements.compactMap(\.entry?.application)
    }
}

// MARK: - Fixtures

@MainActor
enum Fixture {
    static let builtIn = DisplayInfo(
        id: DisplayID(1), name: "Built-in Display", isPrimary: true)
    static let external = DisplayInfo(id: DisplayID(2), name: "DELL U2720Q")

    /// The built-in display with Apple's Dock on it.
    static let builtInWithDock = DisplayInfo(
        id: DisplayID(1), name: "Built-in Display", isPrimary: true, hostsSystemDock: true)

    static let safari = ApplicationInfo(
        bundleIdentifier: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app")
    static let terminal = ApplicationInfo(
        bundleIdentifier: "com.apple.Terminal", name: "Terminal",
        path: "/System/Applications/Utilities/Terminal.app")
    static let preview = ApplicationInfo(
        bundleIdentifier: "com.apple.Preview", name: "Preview",
        path: "/System/Applications/Preview.app")

    static let downloads = DockFolder(
        name: "Downloads", path: "/Users/test/Downloads/")

    /// A `directory-tile`, in the shape a live `com.apple.dock` stores it —
    /// trailing slash and all, which is what makes the folder's name need
    /// deriving rather than reading off the end of the path.
    static func directoryTile(_ folder: DockFolder) -> [String: Any] {
        [
            "GUID": 666_512_234,
            "tile-type": "directory-tile",
            "tile-data": [
                "file-label": folder.name,
                "displayas": folder.displayAs.rawValue,
                "showas": folder.showAs.rawValue,
                "arrangement": 2,
                "preferreditemsize": -1,
                "file-data": [
                    "_CFURLString": "file://\(folder.path)",
                    "_CFURLStringType": 15,
                ],
            ],
        ]
    }

    /// A Dock tile in the shape `com.apple.dock` really stores, verified
    /// against a live plist on macOS 26.
    static func tile(_ application: ApplicationInfo) -> [String: Any] {
        [
            "GUID": 666_512_216,
            "tile-type": "file-tile",
            "tile-data": [
                "bundle-identifier": application.bundleIdentifier,
                "file-label": application.name,
                "file-data": [
                    "_CFURLString": "file://\(application.path)/",
                    "_CFURLStringType": 15,
                ],
            ],
        ]
    }
}

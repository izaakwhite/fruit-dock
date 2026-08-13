/// Supplies the currently connected displays.
///
/// `NSScreen` cannot be faked and a test cannot unplug a monitor, so every
/// read of the display list goes through this protocol. The real
/// implementation lives in the app target; tests substitute a stub.
@MainActor
public protocol DisplayProviding: AnyObject {
    var connectedDisplays: [DisplayInfo] { get }

    /// Invokes `handler` whenever displays are added, removed, reconfigured,
    /// or the system Dock moves between them. Replaces any previous handler.
    func onDisplayChange(_ handler: @escaping () -> Void)
}

/// Supplies running applications and performs launch/activate.
///
/// Wraps `NSWorkspace`, which is process-global and cannot be faked, so all
/// access funnels through here.
@MainActor
public protocol ApplicationProviding: AnyObject {
    /// Apps with a visible presence — the ones a dock should show.
    var runningApplications: [ApplicationInfo] { get }

    /// Invokes `handler` when an app launches or terminates. Implementations
    /// should observe notifications rather than poll: polling on a timer is
    /// the usual way an idle menu-bar agent blows its CPU budget (NFR-1).
    func onRunningApplicationsChange(_ handler: @escaping () -> Void)

    /// Brings the app to the front, launching it first if needed. FR-3.2.
    ///
    /// `displayID` is the screen whose dock was clicked. Implementations
    /// should place the app's windows there when they are able; doing so
    /// requires Accessibility permission, so this is a best effort and must
    /// still activate the app when placement is unavailable.
    func activateOrLaunch(_ application: ApplicationInfo, on displayID: DisplayID?)

    /// Asks the app to quit. FR-3.5.
    func quit(_ application: ApplicationInfo)

    /// Reveals the Trash in Finder.
    func openTrash()
}

/// Reads Apple's Dock's own preferences.
///
/// Read-only, and deliberately so: `com.apple.dock` is another application's
/// defaults domain, the Dock rewrites it whenever the user rearranges a tile,
/// and nothing good comes of two processes writing the same preferences.
///
/// Values come back in their raw property-list shape rather than as
/// applications, because interpreting that shape is a decision and decisions
/// belong in the domain — `SystemDockPreferences` does the interpreting, and
/// is testable from literal fixtures precisely because this protocol does not.
@MainActor
public protocol SystemDockReading: AnyObject {
    /// Raw `persistent-apps` tiles, in the order the user arranged them.
    var persistentApplicationTiles: [Any] { get }

    /// Raw `recent-apps` tiles, most recent first.
    var recentApplicationTiles: [Any] { get }

    /// The user's "Show recent applications in Dock" setting, or nil when they
    /// have never changed it — a missing key is not the same as `false`.
    var showsRecentApplications: Bool? { get }

    /// Apple's Dock icon size (`tilesize`), or nil when never changed from the
    /// default. Raw and unvalidated, as with the tiles: interpreting it is the
    /// domain's job, so the clamping can be tested from literal values.
    var tileSize: Double? { get }
}

/// Supplies the applications installed on this Mac.
///
/// Wraps `FileManager` and `Bundle`, which read a filesystem a test has no
/// business depending on: the set of installed applications differs on every
/// machine, so a test written against the real one asserts nothing.
@MainActor
public protocol InstalledApplicationProviding: AnyObject {
    /// Every application bundle in the standard locations, unsorted.
    var installedApplications: [ApplicationInfo] { get }

    /// Whether an application bundle is still present at `path`.
    ///
    /// Apple's Dock keeps tiles for applications that have since been deleted,
    /// and importing one yields an icon that cannot draw and a click that
    /// cannot launch.
    func applicationExists(atPath path: String) -> Bool
}

/// Persists user settings.
///
/// Abstracted for the same reason as `DisplayProviding`: `UserDefaults`
/// reaches for global process state, which makes tests order-dependent.
@MainActor
public protocol ConfigurationStoring: AnyObject {
    /// Returns nil when nothing has been persisted yet, or when stored data
    /// is unreadable — callers fall back to `DockConfiguration.default`.
    func load() -> DockConfiguration?
    func save(_ configuration: DockConfiguration)
}

/// Displays dock surfaces on screens.
///
/// The coordinator decides *which* displays should have a dock and *what* goes
/// in it; this protocol is how those decisions become visible. Keeping window
/// creation behind it means the coordinator can be tested without opening a
/// single window — the gap that let a completely non-functional feature ship
/// with every test passing.
@MainActor
public protocol DockPresenting: AnyObject {
    /// Displays that currently have a dock surface.
    var presentedDisplays: Set<DisplayID> { get }

    func present(on display: DisplayInfo, configuration: DockConfiguration)
    func dismiss(_ displayID: DisplayID)
    func dismissAll()

    /// Re-places an existing surface, e.g. after a resolution change.
    func reposition(_ displayID: DisplayID)

    /// Renders `elements` on every presented surface.
    func render(_ elements: [DockElement])

    /// Rebuilds surface chrome after a system appearance change.
    func refreshAppearance()
}

/// What a dock surface asks of the coordinator when the user acts.
@MainActor
public protocol DockActionHandling: AnyObject {
    /// `displayID` identifies which display's dock was clicked, so the app can
    /// be brought up on that screen rather than wherever macOS would default.
    func activate(_ application: ApplicationInfo, on displayID: DisplayID?)
    func quit(_ application: ApplicationInfo)
    func togglePin(_ application: ApplicationInfo)
    func isPinned(_ application: ApplicationInfo) -> Bool
    func openTrash()
}

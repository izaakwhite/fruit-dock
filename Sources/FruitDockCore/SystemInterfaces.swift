/// Supplies the currently connected displays.
///
/// `NSScreen` cannot be faked and a test cannot unplug a monitor, so every
/// read of the display list goes through this protocol. The real
/// implementation lives in the app target; tests substitute a stub.
@MainActor
public protocol DisplayProviding: AnyObject {
    var connectedDisplays: [DisplayInfo] { get }

    /// Invokes `handler` whenever displays are added, removed, or
    /// reconfigured. Replaces any previously registered handler.
    func onDisplayChange(_ handler: @escaping () -> Void)
}

/// Persists user settings.
///
/// Abstracted for the same reason as `DisplayProviding`: `UserDefaults`
/// reaches for global process state, which makes tests order-dependent.
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
    func activateOrLaunch(_ application: ApplicationInfo)

    /// Asks the app to quit. FR-3.5.
    func quit(_ application: ApplicationInfo)
}

@MainActor
public protocol ConfigurationStoring: AnyObject {
    /// Returns nil when nothing has been persisted yet, or when stored data
    /// is unreadable — callers fall back to `DockConfiguration.default`.
    func load() -> DockConfiguration?
    func save(_ configuration: DockConfiguration)
}

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
@MainActor
public protocol ConfigurationStoring: AnyObject {
    /// Returns nil when nothing has been persisted yet, or when stored data
    /// is unreadable — callers fall back to `DockConfiguration.default`.
    func load() -> DockConfiguration?
    func save(_ configuration: DockConfiguration)
}

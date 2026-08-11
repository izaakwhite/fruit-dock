/// One slot in the dock.
public struct DockEntry: Equatable, Sendable, Identifiable {
    public var id: String { application.bundleIdentifier }

    public let application: ApplicationInfo

    /// Pinned apps stay put whether or not they are running.
    public let isPinned: Bool

    /// Drives the running indicator. FR-3.3.
    public let isRunning: Bool

    public init(application: ApplicationInfo, isPinned: Bool, isRunning: Bool) {
        self.application = application
        self.isPinned = isPinned
        self.isRunning = isRunning
    }
}

/// Decides what the dock shows and in what order.
///
/// A pure function, for the same reason as `DisplayReconciler`: the rules
/// about pinned versus running apps are worth testing, and none of them need
/// a window to evaluate.
public enum DockContentBuilder {

    /// - Parameters:
    ///   - pinned: user-pinned apps, in user order. Order is preserved —
    ///     a dock that reshuffles itself is unusable.
    ///   - running: apps currently running, from the system.
    ///   - showsRunningApps: whether unpinned running apps appear after the
    ///     pinned ones. FR-3.4.
    public static func entries(
        pinned: [DockItem],
        running: [ApplicationInfo],
        showsRunningApps: Bool
    ) -> [DockEntry] {
        let runningIDs = Set(running.map(\.bundleIdentifier))

        // Pinned apps first, in the order the user arranged them.
        var entries = pinned.map { item in
            DockEntry(
                application: item.application,
                isPinned: true,
                isRunning: runningIDs.contains(item.bundleIdentifier)
            )
        }

        guard showsRunningApps else { return entries }

        // Then anything running that is not already pinned. Deduplicating on
        // bundle identifier keeps an app from appearing twice when it is both
        // pinned and running.
        let pinnedIDs = Set(pinned.map(\.bundleIdentifier))
        entries += running
            .filter { !pinnedIDs.contains($0.bundleIdentifier) }
            .map { DockEntry(application: $0, isPinned: false, isRunning: true) }

        return entries
    }
}

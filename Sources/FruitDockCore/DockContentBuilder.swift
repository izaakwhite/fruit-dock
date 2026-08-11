/// One application slot in the dock.
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

/// Everything the dock can draw, in order.
///
/// Apple's Dock is not a uniform row of apps: Finder is anchored first, and a
/// separator divides applications from Trash at the far end. Modelling those
/// as element kinds rather than special-casing indices in the view keeps the
/// layout rules testable.
public enum DockElement: Equatable, Sendable, Identifiable {
    case app(DockEntry)
    case separator
    case trash

    public var id: String {
        switch self {
        case .app(let entry): entry.id
        case .separator: "—separator—"
        case .trash: "—trash—"
        }
    }

    public var entry: DockEntry? {
        if case .app(let entry) = self { return entry }
        return nil
    }
}

/// Decides what the dock shows and in what order.
///
/// A pure function, for the same reason as `DisplayReconciler`: the rules
/// about ordering, anchoring, and deduplication are worth testing, and none
/// of them need a window to evaluate.
public enum DockContentBuilder {

    /// Finder is always present and always first, matching Apple's Dock,
    /// where it cannot be removed or reordered.
    public static let finderBundleIdentifier = "com.apple.finder"

    /// - Parameters:
    ///   - pinned: user-pinned apps, in user order. Order is preserved —
    ///     a dock that reshuffles itself is unusable.
    ///   - running: apps currently running, from the system.
    ///   - showsRunningApps: whether unpinned running apps appear after the
    ///     pinned ones. FR-3.4.
    ///   - showsTrash: whether the separator and Trash are appended.
    public static func elements(
        pinned: [DockItem],
        running: [ApplicationInfo],
        showsRunningApps: Bool,
        showsTrash: Bool = true
    ) -> [DockElement] {
        let runningIDs = Set(running.map(\.bundleIdentifier))
        var seen = Set<String>()
        var apps: [DockEntry] = []

        /// Appends unless this bundle is already placed. Finder in particular
        /// can arrive from three directions — anchored, pinned, and running —
        /// and must still appear exactly once.
        func append(_ application: ApplicationInfo, isPinned: Bool) {
            guard seen.insert(application.bundleIdentifier).inserted else { return }
            apps.append(
                DockEntry(
                    application: application,
                    isPinned: isPinned,
                    isRunning: runningIDs.contains(application.bundleIdentifier)
                )
            )
        }

        // Finder is anchored first. Prefer the system's own record of it so
        // the path and name are real; fall back to a pinned copy.
        let finder = running.first { $0.bundleIdentifier == finderBundleIdentifier }
            ?? pinned.first { $0.bundleIdentifier == finderBundleIdentifier }?.application
        if let finder {
            append(finder, isPinned: true)
        }

        for item in pinned {
            append(item.application, isPinned: true)
        }

        if showsRunningApps {
            for application in running {
                append(application, isPinned: false)
            }
        }

        var elements = apps.map(DockElement.app)
        if showsTrash {
            elements.append(.separator)
            elements.append(.trash)
        }
        return elements
    }
}

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
    case folder(DockFolder)
    case minimizedWindow(WindowTile)
    case separator
    case trash

    public var id: String {
        switch self {
        case .app(let entry): entry.id
        case .folder(let folder): "folder:\(folder.path)"
        case .minimizedWindow(let window): "window:\(window.id)"
        case .separator: "—separator—"
        case .trash: "—trash—"
        }
    }

    public var entry: DockEntry? {
        if case .app(let entry) = self { return entry }
        return nil
    }

    /// Whether this element is drawn at full icon size. Separators are not,
    /// which is what the fitting calculation in `DockSizing` needs to know.
    public var isTile: Bool {
        if case .separator = self { return false }
        return true
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
    ///   - recents: recently used apps, from Apple's Dock, most recent first.
    ///   - showsRunningApps: whether unpinned running apps appear after the
    ///     pinned ones. FR-3.4.
    ///   - showsRecentApps: whether the recents section appears at all.
    ///   - showsTrash: whether the separator and Trash are appended.
    public static func elements(
        pinned: [DockItem],
        running: [ApplicationInfo],
        recents: [ApplicationInfo] = [],
        folders: [DockFolder] = [],
        minimizedWindows: [WindowTile] = [],
        showsRunningApps: Bool,
        showsRecentApps: Bool = false,
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

        // Recents are a section of their own, behind a separator, so a tile
        // the user never chose to put there cannot be mistaken for one they
        // did. Anything already placed above is skipped rather than repeated:
        // an app that is pinned or running is on the dock already, and Apple's
        // Dock likewise never lists it twice.
        if showsRecentApps {
            let recentEntries = recents
                .filter { seen.insert($0.bundleIdentifier).inserted }
                .map { application in
                    DockElement.app(
                        DockEntry(
                            application: application,
                            isPinned: false,
                            isRunning: runningIDs.contains(application.bundleIdentifier)
                        )
                    )
                }
            if !recentEntries.isEmpty {
                // A separator with nothing before it is a stray line, which is
                // what an empty dock with recents would otherwise draw.
                if !elements.isEmpty { elements.append(.separator) }
                elements.append(contentsOf: recentEntries)
            }
        }

        // Folders, minimised windows and the Trash share the last section, as
        // they do in Apple's Dock. None of them is an application: there is
        // nothing to launch, nothing to quit, and no running state — which is
        // exactly what the separator before them is telling the reader.
        let others: [DockElement] =
            folders.map(DockElement.folder)
            + minimizedWindows.map(DockElement.minimizedWindow)

        if !others.isEmpty || showsTrash {
            if !elements.isEmpty { elements.append(.separator) }
            elements.append(contentsOf: others)
            if showsTrash { elements.append(.trash) }
        }
        return elements
    }
}

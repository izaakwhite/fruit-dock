/// An application the dock can show.
///
/// Carries no icon: `NSImage` is an AppKit type and would drag the UI
/// framework into the domain. The view layer resolves an icon from `path`
/// when it draws.
public struct ApplicationInfo: Hashable, Sendable, Identifiable {
    public var id: String { bundleIdentifier }

    public let bundleIdentifier: String
    public let name: String

    /// Filesystem path to the `.app` bundle, used for launching and for
    /// icon lookup.
    public let path: String

    public init(bundleIdentifier: String, name: String, path: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
    }
}

/// An application the user has explicitly pinned.
///
/// Persisted, so it is a distinct type from `ApplicationInfo` — a pinned app
/// must survive not being installed or running at the moment we read it.
public struct DockItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String { bundleIdentifier }

    public let bundleIdentifier: String
    public let name: String
    public let path: String

    public init(bundleIdentifier: String, name: String, path: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
    }

    public init(_ application: ApplicationInfo) {
        self.init(
            bundleIdentifier: application.bundleIdentifier,
            name: application.name,
            path: application.path
        )
    }

    public var application: ApplicationInfo {
        ApplicationInfo(bundleIdentifier: bundleIdentifier, name: name, path: path)
    }
}

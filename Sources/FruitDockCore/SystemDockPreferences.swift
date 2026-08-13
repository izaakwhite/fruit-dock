import Foundation

/// Reads Apple's Dock preferences, which are property lists rather than
/// anything we designed.
///
/// The values arrive in their raw plist shape — nested dictionaries of `Any` —
/// and turning that into applications is a decision, so it lives here as a pure
/// function rather than in the reader that fetches it. That is what lets every
/// malformed shape below be exercised from a literal fixture with no
/// `UserDefaults` in sight.
///
/// Structure confirmed against a real `com.apple.dock` on macOS 26: each entry
/// of `persistent-apps` and `recent-apps` is a dictionary with `tile-type` and
/// a `tile-data` dictionary, whose `file-data` holds a percent-encoded
/// `_CFURLString`. `bundle-identifier` and `file-label` sit alongside it.
public enum SystemDockPreferences {

    /// Apple's Dock's own defaults domain. Read-only: it is another app's
    /// state, and the Dock rewrites it whenever the user rearranges anything.
    public static let defaultsSuiteName = "com.apple.dock"

    public static let persistentAppsKey = "persistent-apps"
    public static let recentAppsKey = "recent-apps"
    public static let showRecentsKey = "show-recents"

    // MARK: - Recents preference

    /// What macOS does when "Show recent applications in Dock" was never
    /// touched: the key is simply absent, and the feature is on.
    public static let showsRecentApplicationsByDefault = true

    /// - Parameter stored: the raw `show-recents` value, nil when unset.
    public static func showsRecentApplications(_ stored: Bool?) -> Bool {
        stored ?? showsRecentApplicationsByDefault
    }

    // MARK: - Icon size

    public static let tileSizeKey = "tilesize"

    /// The Dock's own default, used when `tilesize` has never been changed.
    public static let defaultTileSize: Double = 48

    /// The range Apple's own Dock size slider spans. A value outside it did not
    /// come from that slider, and is more likely a stale or corrupt key than an
    /// instruction worth honouring.
    public static let tileSizeRange: ClosedRange<Double> = 16...128

    /// The user's Dock icon size, as a size we can safely draw at.
    ///
    /// Seeding from this rather than a constant is the difference between a
    /// dock that matches the one already on screen and one that merely sits
    /// near it. Someone who enlarged their Dock did so because they wanted
    /// larger icons, and that intent should carry over.
    ///
    /// - Parameter stored: the raw `tilesize` value, nil when never changed.
    public static func tileSize(_ stored: Double?) -> Double {
        guard let stored, stored.isFinite else { return defaultTileSize }
        return min(max(stored, tileSizeRange.lowerBound), tileSizeRange.upperBound)
    }

    // MARK: - Tiles

    /// Applications named by an array of Dock tiles, in Dock order.
    ///
    /// Every failure is a skip rather than a throw. This data belongs to
    /// another process and is written by versions of macOS we have not seen;
    /// one unrecognised tile must cost that tile, not the whole import.
    ///
    /// - Parameter isInstalled: whether a bundle is still present at a path.
    ///   The Dock keeps tiles for applications that have since been deleted,
    ///   and importing one produces an icon that cannot draw and a click that
    ///   cannot launch. Injected rather than read here so the domain layer
    ///   stays free of the filesystem.
    public static func applications(
        fromTiles tiles: [Any],
        isInstalled: (String) -> Bool = { _ in true }
    ) -> [ApplicationInfo] {
        var seen = Set<String>()
        var applications: [ApplicationInfo] = []

        for tile in tiles {
            guard let application = self.application(fromTile: tile),
                  isInstalled(application.path),
                  seen.insert(application.bundleIdentifier).inserted
            else { continue }

            applications.append(application)
        }
        return applications
    }

    /// One tile, or nil when it does not describe an application we can open.
    static func application(fromTile tile: Any) -> ApplicationInfo? {
        guard let tile = tile as? [String: Any],
              let tileData = tile["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any],
              let urlString = fileData["_CFURLString"] as? String,
              let path = filePath(from: urlString)
        else { return nil }

        return ApplicationInfo(
            bundleIdentifier: identifier(fromTileData: tileData, path: path),
            name: name(fromTileData: tileData, path: path),
            path: path
        )
    }

    /// Turns `file:///Applications/Prime%20Video.app/` into
    /// `/Applications/Prime Video.app`.
    ///
    /// `URL` is used for the percent-decoding, which hand-rolled string
    /// surgery gets wrong on exactly the applications with spaces in their
    /// names. It parses far more than file URLs, though — a bare string comes
    /// back as a schemeless URL rather than nil — so the scheme is checked
    /// explicitly.
    static func filePath(from urlString: String) -> String? {
        guard let url = URL(string: urlString), url.scheme == "file" else { return nil }

        let path = url.path
        return path.isEmpty ? nil : path
    }

    /// Prefers the Dock's own record of the bundle identifier, which every
    /// tile on a current macOS carries.
    ///
    /// Falls back to the path when it is missing. Identity has to be unique
    /// and stable — it is what deduplication and pinning key on — and the path
    /// is both, while a guess derived from the app's name could collide with a
    /// real identifier. Launching works from the path regardless.
    static func identifier(fromTileData tileData: [String: Any], path: String) -> String {
        guard let identifier = tileData["bundle-identifier"] as? String,
              !identifier.isEmpty
        else { return path }

        return identifier
    }

    static func name(fromTileData tileData: [String: Any], path: String) -> String {
        if let label = tileData["file-label"] as? String, !label.isEmpty {
            return label
        }

        let component = path.split(separator: "/").last.map(String.init) ?? path
        return component.hasSuffix(".app") ? String(component.dropLast(4)) : component
    }
}

/// Which edge of a display the dock is pinned to.
public enum DockEdge: String, Codable, Sendable, CaseIterable {
    case bottom, left, right, top

    /// Left and right edges stack icons vertically.
    public var isVertical: Bool { self == .left || self == .right }
}

/// User-facing settings, persisted across launches.
public struct DockConfiguration: Codable, Equatable, Sendable {
    /// Bumped whenever the persisted shape changes incompatibly.
    ///
    /// Present from the very first write. Adding a version field costs one
    /// line now and is impossible to add retroactively — released builds will
    /// already have written unversioned data.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int

    /// Displays the user has explicitly switched *off*.
    ///
    /// Storing the disabled set rather than the enabled set means a newly
    /// connected display shows a dock by default, with no special-casing:
    /// absence from this set is the desired default.
    public var disabledDisplays: Set<DisplayID>

    public var edge: DockEdge

    /// Icon edge length in points, before any hover magnification.
    public var iconSize: Double

    /// Whether tiles grow under the cursor. Off by default, matching macOS.
    public var magnifies: Bool

    /// The size a magnified tile grows to, in points — Apple's `largesize`.
    ///
    /// Meaningless on its own: what matters is its ratio to `iconSize`, and a
    /// value at or below it means no magnification rather than shrinking. See
    /// `DockMagnification.maximumScale`.
    public var largeIconSize: Double

    /// Apps the user pinned, in the order they arranged them. FR-3.1.
    public var pinnedItems: [DockItem]

    /// Whether running-but-unpinned apps appear after the pinned ones. FR-3.4.
    public var showsRunningApps: Bool

    /// Whether the recently-used apps section appears after the running ones.
    ///
    /// Off in the struct's own defaults, and seeded on first launch from the
    /// system Dock's `show-recents` — a user who turned recents off there has
    /// already said what they want, and a section nobody asked for appearing
    /// after an upgrade is worse than one they have to switch on.
    public var showsRecentApps: Bool

    /// Whether to leave the display that currently hosts Apple's Dock alone.
    ///
    /// On by default. Two docks on one screen is redundant and confusing, and
    /// the system Dock cannot be removed — `Dock.app` also owns Mission
    /// Control, Spaces, and Launchpad, so it is not ours to replace. Filling
    /// in the displays it is absent from gives every screen exactly one dock.
    public var avoidsSystemDockDisplay: Bool

    public init(
        schemaVersion: Int = DockConfiguration.currentSchemaVersion,
        disabledDisplays: Set<DisplayID> = [],
        edge: DockEdge = .bottom,
        iconSize: Double = 48,
        magnifies: Bool = false,
        largeIconSize: Double = 64,
        pinnedItems: [DockItem] = [],
        showsRunningApps: Bool = true,
        showsRecentApps: Bool = false,
        avoidsSystemDockDisplay: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.disabledDisplays = disabledDisplays
        self.edge = edge
        self.iconSize = iconSize
        self.magnifies = magnifies
        self.largeIconSize = largeIconSize
        self.pinnedItems = pinnedItems
        self.showsRunningApps = showsRunningApps
        self.showsRecentApps = showsRecentApps
        self.avoidsSystemDockDisplay = avoidsSystemDockDisplay
    }

    /// Sane fallback when nothing has been persisted, or when persisted data
    /// cannot be read.
    public static let `default` = DockConfiguration()

    // MARK: - Display enablement

    public func isEnabled(_ display: DisplayID) -> Bool {
        !disabledDisplays.contains(display)
    }

    public mutating func setEnabled(_ enabled: Bool, for display: DisplayID) {
        if enabled {
            disabledDisplays.remove(display)
        } else {
            disabledDisplays.insert(display)
        }
    }

    // MARK: - Pinning

    public func isPinned(_ bundleIdentifier: String) -> Bool {
        pinnedItems.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    public mutating func pin(_ application: ApplicationInfo) {
        guard !isPinned(application.bundleIdentifier) else { return }
        pinnedItems.append(DockItem(application))
    }

    public mutating func unpin(_ bundleIdentifier: String) {
        pinnedItems.removeAll { $0.bundleIdentifier == bundleIdentifier }
    }

    // MARK: - Decoding

    /// Decoded field by field with defaults rather than relying on the
    /// synthesized initialiser.
    ///
    /// Settings written by an older build are missing any key added since.
    /// Synthesized `Codable` treats a missing key as an error, which would
    /// throw away every setting the user had — so each field falls back to its
    /// default instead. This is what makes adding a field a non-event.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DockConfiguration()

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? fallback.schemaVersion
        disabledDisplays = try container.decodeIfPresent(Set<DisplayID>.self, forKey: .disabledDisplays)
            ?? fallback.disabledDisplays
        edge = try container.decodeIfPresent(DockEdge.self, forKey: .edge)
            ?? fallback.edge
        iconSize = try container.decodeIfPresent(Double.self, forKey: .iconSize)
            ?? fallback.iconSize
        magnifies = try container.decodeIfPresent(Bool.self, forKey: .magnifies)
            ?? fallback.magnifies
        largeIconSize = try container.decodeIfPresent(Double.self, forKey: .largeIconSize)
            ?? fallback.largeIconSize
        pinnedItems = try container.decodeIfPresent([DockItem].self, forKey: .pinnedItems)
            ?? fallback.pinnedItems
        showsRunningApps = try container.decodeIfPresent(Bool.self, forKey: .showsRunningApps)
            ?? fallback.showsRunningApps
        showsRecentApps = try container.decodeIfPresent(Bool.self, forKey: .showsRecentApps)
            ?? fallback.showsRecentApps
        avoidsSystemDockDisplay = try container.decodeIfPresent(Bool.self, forKey: .avoidsSystemDockDisplay)
            ?? fallback.avoidsSystemDockDisplay
    }
}

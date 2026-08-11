/// Which edge of a display the dock is pinned to.
public enum DockEdge: String, Codable, Sendable, CaseIterable {
    case bottom, left, right, top
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

    public init(
        schemaVersion: Int = DockConfiguration.currentSchemaVersion,
        disabledDisplays: Set<DisplayID> = [],
        edge: DockEdge = .bottom,
        iconSize: Double = 48
    ) {
        self.schemaVersion = schemaVersion
        self.disabledDisplays = disabledDisplays
        self.edge = edge
        self.iconSize = iconSize
    }

    /// Sane fallback when nothing has been persisted, or when persisted data
    /// cannot be read.
    public static let `default` = DockConfiguration()

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
}

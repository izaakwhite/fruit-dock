/// The fixed measurements of a dock bar, in points.
///
/// In the domain rather than the view because the dock's *length* has to be
/// known before it can be decided whether it fits — and a dock that does not
/// fit its display is the thing that most needs deciding about.
public struct DockMetrics: Equatable, Sendable {
    /// Gap between adjacent tiles.
    public var spacing: Double

    /// Inset from the bar's edge to the first tile, on every side.
    public var padding: Double

    /// Room beneath a tile for the running indicator.
    public var indicatorLane: Double

    /// A separator occupies far less room than a tile.
    public var separatorExtent: Double

    public init(
        spacing: Double = 6,
        padding: Double = 8,
        indicatorLane: Double = 7,
        separatorExtent: Double = 11
    ) {
        self.spacing = spacing
        self.padding = padding
        self.indicatorLane = indicatorLane
        self.separatorExtent = separatorExtent
    }

    public static let `default` = DockMetrics()

    /// How long a bar holding these elements would be, along its long axis.
    ///
    /// - Parameters:
    ///   - tileCount: elements drawn at full icon size.
    ///   - separatorCount: elements drawn as separators instead.
    public func length(tileCount: Int, separatorCount: Int = 0, iconSize: Double) -> Double {
        let total = tileCount + separatorCount
        guard total > 0 else { return iconSize }

        return padding * 2
            + Double(tileCount) * iconSize
            + Double(separatorCount) * separatorExtent
            + Double(total - 1) * spacing
    }

    /// The bar's other dimension, which depends only on the icon size.
    public func breadth(iconSize: Double) -> Double {
        padding * 2 + iconSize + indicatorLane
    }
}

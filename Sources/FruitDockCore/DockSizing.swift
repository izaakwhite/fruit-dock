/// Scales the dock to the display it is drawn on.
///
/// One fixed icon size across every display gets the tradeoff wrong in both
/// directions: sized for a laptop it looks lost on a large external monitor,
/// and sized for the monitor it crowds the laptop.
public enum DockSizing {

    /// The display height `DockConfiguration.iconSize` is calibrated against.
    /// Roughly a 1080p desktop display, and close to a 14-inch MacBook Pro's
    /// logical height, so the common cases land near the configured value.
    public static let referenceHeight: Double = 1080

    public static let minimumIconSize: Double = 24
    public static let maximumIconSize: Double = 128

    /// How much of the display's difference in size to actually apply.
    ///
    /// Scaling in full makes a large monitor's dock cartoonish. Icon size
    /// tracks how far away the screen is more than how big it is, and someone
    /// with a 4K display is not sitting twice as far back — so half the
    /// difference reads as proportionate where all of it does not.
    public static let dampening: Double = 0.5

    /// - Parameters:
    ///   - base: the configured icon size, as calibrated for `referenceHeight`.
    ///   - displayHeight: the display's height in *points*, not pixels. macOS
    ///     already reports logical points, so a HiDPI display does not report
    ///     double and this needs no backing-scale correction of its own.
    public static func iconSize(
        base: Double,
        displayHeight: Double,
        referenceHeight: Double = referenceHeight
    ) -> Double {
        // A display cannot report a sensible height while it is being
        // reconfigured, and neither zero nor a negative belongs in a divisor.
        guard base > 0, displayHeight > 0, referenceHeight > 0 else {
            return base.clamped(to: minimumIconSize...maximumIconSize)
        }

        let ratio = displayHeight / referenceHeight
        let scale = 1 + (ratio - 1) * dampening

        // Rounded, because a fractional icon size renders blurry on a display
        // whose backing scale does not divide it evenly.
        return (base * scale).rounded().clamped(to: minimumIconSize...maximumIconSize)
    }

    /// The largest share of a display's length the dock may occupy.
    ///
    /// A dock spanning its whole screen stops reading as a dock. Apple's own
    /// grows until it must shrink, and this is the point at which ours must.
    public static let maximumLengthFraction: Double = 0.9

    /// An icon size that both suits the display and lets the dock fit on it.
    ///
    /// Scaling by display height alone is not enough, and on real hardware it
    /// is barely enough to notice: a 13-inch laptop reports 900 points of
    /// height against an external monitor's 1080, so the two docks come out
    /// within a few points of each other despite ten inches of difference in
    /// physical size. What actually distinguishes them is how much room there
    /// is to spend — 1440 points of width against 1920 — and how many tiles
    /// have to go in it.
    ///
    /// So the height-derived size is treated as a preference and then made to
    /// fit. A dock of twenty apps at 66pt needs more than 1440 points and would
    /// otherwise be clamped to the screen's width by `DockLayout`, squeezing
    /// the tiles rather than sizing them.
    ///
    /// - Parameters:
    ///   - availableLength: the display's extent along the dock's long axis —
    ///     width for a horizontal dock, height for a vertical one.
    public static func iconSize(
        base: Double,
        displayHeight: Double,
        tileCount: Int,
        separatorCount: Int = 0,
        availableLength: Double,
        metrics: DockMetrics = .default,
        referenceHeight: Double = referenceHeight
    ) -> Double {
        let preferred = iconSize(
            base: base, displayHeight: displayHeight, referenceHeight: referenceHeight)

        guard tileCount > 0, availableLength > 0 else { return preferred }

        let budget = availableLength * maximumLengthFraction
        let needed = metrics.length(
            tileCount: tileCount, separatorCount: separatorCount, iconSize: preferred)

        guard needed > budget else { return preferred }

        // Solved rather than stepped down: only the tiles can give, since
        // padding, spacing and separators are all fixed, so inverting
        // `DockMetrics.length` for `iconSize` gives the largest size that fits
        // in one step.
        //
        //   budget = padding*2 + tiles*size + separators*extent + (total-1)*spacing
        //
        // Note this cannot reuse `length(tileCount: 0, ...)` to total the fixed
        // parts: that call reports the size of an *empty* dock, which is one
        // icon wide by definition, and counting it here shrank every dock by a
        // whole tile more than it needed to.
        let total = tileCount + separatorCount
        let fixed = metrics.padding * 2
            + Double(separatorCount) * metrics.separatorExtent
            + Double(total - 1) * metrics.spacing

        let forTiles = budget - fixed
        guard forTiles > 0 else { return minimumIconSize }

        return (forTiles / Double(tileCount))
            .rounded(.down)
            .clamped(to: minimumIconSize...preferred)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

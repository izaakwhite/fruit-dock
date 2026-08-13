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
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

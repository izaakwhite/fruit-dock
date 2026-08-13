/// Answers questions about a display that can be settled from its rectangles
/// alone.
public enum DisplayGeometry {

    /// Sub-point differences survive on scaled displays, so an inset only
    /// counts once it is unambiguous.
    public static let insetTolerance: Double = 1

    /// Whether Apple's Dock is currently on this display.
    ///
    /// No API reports this. But `visibleFrame` is `frame` minus what the system
    /// reserves — which is exactly the menu bar and the Dock — so an inset on
    /// the bottom, left, or right edge means the Dock is there.
    ///
    /// **The top edge is deliberately excluded.** That inset is the menu bar,
    /// and on Macs with a camera housing it is larger still. Counting it would
    /// report the primary display as hosting the Dock at all times, and the app
    /// would refuse to draw on the one screen it most needs to.
    ///
    /// A hidden Dock reads as absent, which is correct: it has left the screen
    /// to us.
    ///
    /// - Parameters:
    ///   - frame: the display's full bounds.
    ///   - visibleFrame: its bounds minus system-reserved space. Both in global
    ///     coordinates, so the two must belong to the same display.
    public static func hostsSystemDock(
        frame: ScreenRect,
        visibleFrame: ScreenRect,
        tolerance: Double = insetTolerance
    ) -> Bool {
        let bottomInset = visibleFrame.minY - frame.minY
        let leftInset = visibleFrame.minX - frame.minX
        let rightInset = frame.maxX - visibleFrame.maxX

        return bottomInset > tolerance
            || leftInset > tolerance
            || rightInset > tolerance
    }
}

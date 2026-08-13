/// Places the dock against an edge of a display.
///
/// Pure arithmetic, deliberately. This used to take an `NSScreen` and live in
/// the AppKit layer, where it could only be checked by looking at a monitor —
/// and where a bug that only shows up on a display whose origin is not zero
/// would go unnoticed on a single-display Mac.
public enum DockLayout {

    /// Gap between the dock and the edge it sits against.
    public static let defaultMargin: Double = 8

    /// - Parameters:
    ///   - size: how large the dock wants to be, from its contents.
    ///   - edge: which edge of the display to sit against.
    ///   - visibleArea: the display's *visible* frame — the full frame minus
    ///     the menu bar and Apple's Dock — in global coordinates. Global, so
    ///     a secondary display's origin is not zero and every result must be
    ///     expressed relative to this rect rather than to zero.
    ///   - margin: distance from the edge.
    public static func frame(
        for size: ScreenSize,
        edge: DockEdge,
        in visibleArea: ScreenRect,
        margin: Double = defaultMargin
    ) -> ScreenRect {
        // A dock wider than its display would run off the side, or onto a
        // neighbouring screen. Enough pinned apps on a small display makes this
        // reachable, so clamp rather than trusting the caller's size.
        let size = ScreenSize(
            width: min(size.width, visibleArea.size.width),
            height: min(size.height, visibleArea.size.height)
        )

        switch edge {
        case .bottom:
            return ScreenRect(
                x: visibleArea.midX - size.width / 2,
                y: visibleArea.minY + margin,
                width: size.width, height: size.height)

        case .top:
            return ScreenRect(
                x: visibleArea.midX - size.width / 2,
                y: visibleArea.maxY - size.height - margin,
                width: size.width, height: size.height)

        case .left:
            return ScreenRect(
                x: visibleArea.minX + margin,
                y: visibleArea.midY - size.height / 2,
                width: size.width, height: size.height)

        case .right:
            return ScreenRect(
                x: visibleArea.maxX - size.width - margin,
                y: visibleArea.midY - size.height / 2,
                width: size.width, height: size.height)
        }
    }
}

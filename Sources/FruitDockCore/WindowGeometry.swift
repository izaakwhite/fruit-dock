/// The arithmetic of putting a window on a chosen display.
///
/// This lives in the domain layer rather than next to the Accessibility calls
/// that use it because it is the part that can be *wrong*, and wrong in a way
/// no amount of running the app on one machine will reveal.
///
/// Cocoa's global space has its origin at the **bottom**-left of the primary
/// display with y increasing upward. The Accessibility API uses the
/// **top**-left with y increasing downward. On a single display whose origin
/// is (0, 0) a reversed conversion still lands the window somewhere plausible,
/// which is exactly how the mistake ships. Literal coordinates in a test are
/// the only cheap way to hold it still.
///
/// Both systems agree on x, and both measure from the *primary* display — the
/// one hosting the menu bar — so its height is the only extra input needed.
public enum WindowGeometry {

    /// Centres a window of `size` within `area`, clamping it to fit.
    ///
    /// Clamping rather than overflowing: a window wider than the target
    /// display would otherwise be centred such that its edges hang onto the
    /// neighbouring screen, which is a worse outcome than the corner. Only the
    /// origin is ever applied — see `WindowPlacer`, which deliberately does not
    /// resize another application's windows — so for an oversized window this
    /// resolves to "pin its top-left to the display's top-left".
    public static func centred(_ size: ScreenSize, in area: ScreenRect) -> ScreenRect {
        let width = min(size.width, area.size.width)
        let height = min(size.height, area.size.height)
        return ScreenRect(
            x: area.midX - width / 2,
            y: area.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Converts a rect from Cocoa's global space into the Accessibility API's.
    ///
    /// The flip is its own inverse: converting twice with the same primary
    /// height returns the original rect.
    public static func accessibilityRect(
        forCocoaRect rect: ScreenRect,
        primaryDisplayHeight: Double
    ) -> ScreenRect {
        ScreenRect(
            origin: ScreenPoint(x: rect.minX, y: primaryDisplayHeight - rect.maxY),
            size: rect.size
        )
    }

    /// The top-left origin the Accessibility API expects for a Cocoa rect.
    public static func accessibilityOrigin(
        forCocoaRect rect: ScreenRect,
        primaryDisplayHeight: Double
    ) -> ScreenPoint {
        accessibilityRect(forCocoaRect: rect, primaryDisplayHeight: primaryDisplayHeight).origin
    }

    /// Whether a window already sits on a display. Both rects must be in the
    /// same coordinate space.
    ///
    /// Compares the window's centre, not its origin. A window straddling two
    /// displays has its origin on one and its body on the other, and the
    /// origin test then reports the screen the user is not looking at. Centre
    /// containment is the rule macOS itself uses to decide which screen a
    /// window belongs to, so matching it means our answer and the user's agree.
    public static func isWindow(_ window: ScreenRect, on display: ScreenRect) -> Bool {
        display.contains(window.centre)
    }
}

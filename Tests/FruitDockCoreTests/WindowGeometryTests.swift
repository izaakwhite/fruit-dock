import Testing
@testable import FruitDockCore

/// Every coordinate here is a literal, and that is the point.
///
/// This arithmetic used to live in the AppKit target, where the only way to
/// exercise it was to plug in a second monitor and look. Cocoa measures from
/// the bottom-left of the primary display and the Accessibility API from the
/// top-left, so a reversed conversion is invisible on one display whose origin
/// is (0, 0) — the configuration every developer has.
///
/// The displays below are the ones that expose it: one above the primary, one
/// below it, and one to the left with a negative origin.
@Suite("Window geometry")
struct WindowGeometryTests {

    /// A 1920×1080 primary. Both coordinate systems are anchored to it, so its
    /// height is the only conversion input.
    let primaryHeight: Double = 1080
    let primary = ScreenRect(x: 0, y: 0, width: 1920, height: 1080)

    /// Cocoa places a display above the primary at a positive y.
    let above = ScreenRect(x: 0, y: 1080, width: 1920, height: 1440)

    /// And one below it at a negative y — the origin is the *bottom* left.
    let below = ScreenRect(x: 0, y: -1440, width: 1920, height: 1440)

    /// To the left, x goes negative while y stays put.
    let left = ScreenRect(x: -1920, y: 0, width: 1920, height: 1080)

    // MARK: - Conversion

    @Test("A rect on the primary display is measured down from its top edge")
    func primaryConversion() {
        let window = ScreenRect(x: 100, y: 800, width: 400, height: 200)

        let origin = WindowGeometry.accessibilityOrigin(
            forCocoaRect: window, primaryDisplayHeight: primaryHeight)

        // Its top edge is 1000 above the bottom of a 1080-tall display, so it
        // is 80 below the top. Passing y through unchanged would say 800.
        #expect(origin == ScreenPoint(x: 100, y: 80))
    }

    @Test("A display above the primary has a negative Accessibility origin")
    func displayAbove() {
        let converted = WindowGeometry.accessibilityRect(
            forCocoaRect: above, primaryDisplayHeight: primaryHeight)

        // Above the primary's top edge means above the shared origin.
        #expect(converted.origin == ScreenPoint(x: 0, y: -1440))
        #expect(converted.size == above.size)
    }

    @Test("A display below the primary starts where the primary ends")
    func displayBelow() {
        let converted = WindowGeometry.accessibilityRect(
            forCocoaRect: below, primaryDisplayHeight: primaryHeight)

        // Cocoa calls this display's top edge y = 0; Accessibility calls it
        // 1080, immediately under the primary.
        #expect(converted.origin == ScreenPoint(x: 0, y: 1080))
    }

    @Test("A display to the left keeps its negative x untouched")
    func displayLeft() {
        let converted = WindowGeometry.accessibilityRect(
            forCocoaRect: left, primaryDisplayHeight: primaryHeight)

        // Only y is flipped. A conversion that negated x as well would look
        // right on any arrangement that has no display to the left.
        #expect(converted.origin == ScreenPoint(x: -1920, y: 0))
    }

    @Test("Converting twice returns the rect it started as")
    func conversionIsItsOwnInverse() {
        for rect in [primary, above, below, left] {
            let there = WindowGeometry.accessibilityRect(
                forCocoaRect: rect, primaryDisplayHeight: primaryHeight)
            let back = WindowGeometry.accessibilityRect(
                forCocoaRect: there, primaryDisplayHeight: primaryHeight)
            #expect(back == rect)
        }
    }

    // MARK: - Centring

    @Test("A window centred on the display above lands below that display's top")
    func centredOnDisplayAbove() {
        let centred = WindowGeometry.centred(
            ScreenSize(width: 800, height: 600), in: above)
        #expect(centred == ScreenRect(x: 560, y: 1500, width: 800, height: 600))

        let origin = WindowGeometry.accessibilityOrigin(
            forCocoaRect: centred, primaryDisplayHeight: primaryHeight)

        // The display's top is at Accessibility y = -1440 and the window is
        // 420 down from it, which is (1440 - 600) / 2.
        #expect(origin == ScreenPoint(x: 560, y: -1020))
    }

    @Test("A window centred on the display below lands past the primary's bottom")
    func centredOnDisplayBelow() {
        let centred = WindowGeometry.centred(
            ScreenSize(width: 800, height: 600), in: below)

        let origin = WindowGeometry.accessibilityOrigin(
            forCocoaRect: centred, primaryDisplayHeight: primaryHeight)

        #expect(origin == ScreenPoint(x: 560, y: 1500))
    }

    @Test("A window centred on the display to the left keeps a negative x")
    func centredOnDisplayLeft() {
        let centred = WindowGeometry.centred(
            ScreenSize(width: 800, height: 600), in: left)

        let origin = WindowGeometry.accessibilityOrigin(
            forCocoaRect: centred, primaryDisplayHeight: primaryHeight)

        #expect(origin == ScreenPoint(x: -1360, y: 240))
    }

    @Test("A window larger than the display is pinned to its corner, not overhung")
    func oversizedWindowIsClamped() {
        let centred = WindowGeometry.centred(
            ScreenSize(width: 3000, height: 2000), in: left)

        // Centring a 3000-wide window on a 1920-wide display without clamping
        // would put its origin 540 further left, hanging it onto whatever is
        // next door.
        #expect(centred == ScreenRect(x: -1920, y: 0, width: 1920, height: 1080))

        let origin = WindowGeometry.accessibilityOrigin(
            forCocoaRect: centred, primaryDisplayHeight: primaryHeight)
        #expect(origin == ScreenPoint(x: -1920, y: 0))
    }

    @Test("A window exactly the size of the display sits on its origin")
    func exactFit() {
        let centred = WindowGeometry.centred(
            ScreenSize(width: 1920, height: 1440), in: above)
        #expect(centred == above)
    }

    // MARK: - Already there

    @Test("A window on the display above is recognised as already placed")
    func alreadyOnDisplayAbove() {
        let display = WindowGeometry.accessibilityRect(
            forCocoaRect: above, primaryDisplayHeight: primaryHeight)
        let window = ScreenRect(x: 560, y: -1020, width: 800, height: 600)

        #expect(WindowGeometry.isWindow(window, on: display))

        // Regression: this comparison used to be made against the display's
        // *Cocoa* rect, which is a different coordinate space entirely. It
        // reported "not there" for a window that was, and re-centred a layout
        // the user had already arranged.
        #expect(!above.contains(window.centre))
    }

    @Test("A window on another display is not mistaken for one already placed")
    func notOnDisplay() {
        let display = WindowGeometry.accessibilityRect(
            forCocoaRect: above, primaryDisplayHeight: primaryHeight)
        let onPrimary = ScreenRect(x: 100, y: 80, width: 400, height: 200)

        #expect(!WindowGeometry.isWindow(onPrimary, on: display))
    }

    @Test("A window straddling two displays belongs to the one holding its middle")
    func straddlingWindow() {
        let primaryInAX = WindowGeometry.accessibilityRect(
            forCocoaRect: primary, primaryDisplayHeight: primaryHeight)
        let aboveInAX = WindowGeometry.accessibilityRect(
            forCocoaRect: above, primaryDisplayHeight: primaryHeight)

        // Origin on the display above, but most of the body on the primary.
        let window = ScreenRect(x: 100, y: -100, width: 400, height: 600)

        #expect(WindowGeometry.isWindow(window, on: primaryInAX))
        #expect(!WindowGeometry.isWindow(window, on: aboveInAX))
    }

    @Test("Displays sharing an edge never both claim a point on it")
    func adjacentDisplaysDoNotOverlap() {
        let primaryInAX = WindowGeometry.accessibilityRect(
            forCocoaRect: primary, primaryDisplayHeight: primaryHeight)
        let belowInAX = WindowGeometry.accessibilityRect(
            forCocoaRect: below, primaryDisplayHeight: primaryHeight)

        // Their shared boundary in Accessibility space.
        let seam = ScreenPoint(x: 500, y: 1080)

        #expect(!primaryInAX.contains(seam))
        #expect(belowInAX.contains(seam))
    }
}

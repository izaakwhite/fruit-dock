import Testing
@testable import FruitDockCore

/// Detecting Apple's Dock from rectangles alone. Previously this took an
/// `NSScreen` and could only be checked by dragging the real Dock between
/// monitors by hand.
@Suite("Display geometry")
struct DisplayGeometryTests {

    let frame = ScreenRect(x: 0, y: 0, width: 1512, height: 982)

    /// The menu bar always takes a bite out of the top of the primary display.
    let menuBarHeight: Double = 37
    let dockThickness: Double = 70

    private func visible(
        bottom: Double = 0, left: Double = 0, right: Double = 0, top: Double = 0,
        of frame: ScreenRect
    ) -> ScreenRect {
        ScreenRect(
            x: frame.minX + left,
            y: frame.minY + bottom,
            width: frame.size.width - left - right,
            height: frame.size.height - bottom - top
        )
    }

    // MARK: - Dock present

    @Test("A bottom inset means the Dock is on this display")
    func dockAtBottom() {
        let visibleFrame = visible(bottom: dockThickness, top: menuBarHeight, of: frame)
        #expect(DisplayGeometry.hostsSystemDock(frame: frame, visibleFrame: visibleFrame))
    }

    @Test("A left inset means the Dock is on this display")
    func dockAtLeft() {
        let visibleFrame = visible(left: dockThickness, top: menuBarHeight, of: frame)
        #expect(DisplayGeometry.hostsSystemDock(frame: frame, visibleFrame: visibleFrame))
    }

    @Test("A right inset means the Dock is on this display")
    func dockAtRight() {
        let visibleFrame = visible(right: dockThickness, top: menuBarHeight, of: frame)
        #expect(DisplayGeometry.hostsSystemDock(frame: frame, visibleFrame: visibleFrame))
    }

    // MARK: - Dock absent

    @Test("The menu bar alone does not count as the Dock")
    func menuBarIsNotTheDock() {
        // The load-bearing case. Counting the top inset would report the
        // primary display as always hosting the Dock, and the app would refuse
        // to draw on the one screen it most needs to.
        let visibleFrame = visible(top: menuBarHeight, of: frame)
        #expect(!DisplayGeometry.hostsSystemDock(frame: frame, visibleFrame: visibleFrame))
    }

    @Test("A camera housing does not count as the Dock")
    func cameraHousingIsNotTheDock() {
        // Notched Macs reserve considerably more at the top than a menu bar.
        let visibleFrame = visible(top: 74, of: frame)
        #expect(!DisplayGeometry.hostsSystemDock(frame: frame, visibleFrame: visibleFrame))
    }

    @Test("A display with no insets at all has no Dock")
    func secondaryDisplayWithNothingReserved() {
        #expect(!DisplayGeometry.hostsSystemDock(frame: frame, visibleFrame: frame))
    }

    @Test("A hidden Dock reads as absent")
    func hiddenDockReadsAsAbsent() {
        // Correct rather than a limitation: a hidden Dock has left the screen
        // to us, so we should draw there.
        let visibleFrame = visible(top: menuBarHeight, of: frame)
        #expect(!DisplayGeometry.hostsSystemDock(frame: frame, visibleFrame: visibleFrame))
    }

    // MARK: - Tolerance and offsets

    @Test("A sub-point inset is ignored")
    func subPointInsetIgnored() {
        // Scaled displays leave fractional differences that are not the Dock.
        let visibleFrame = visible(bottom: 0.5, of: frame)
        #expect(!DisplayGeometry.hostsSystemDock(frame: frame, visibleFrame: visibleFrame))
    }

    @Test("Detection works on a display whose origin is not zero")
    func offsetDisplay() {
        // Insets are differences, so they must survive an origin far from zero
        // — including a negative one, for a display arranged to the left.
        for origin in [ScreenPoint(x: 1512, y: 0), ScreenPoint(x: -2560, y: -300)] {
            let offset = ScreenRect(
                origin: origin, size: ScreenSize(width: 2560, height: 1440))

            #expect(
                DisplayGeometry.hostsSystemDock(
                    frame: offset, visibleFrame: visible(bottom: dockThickness, of: offset)))
            #expect(
                !DisplayGeometry.hostsSystemDock(frame: offset, visibleFrame: offset))
        }
    }

    @Test("The Dock and the menu bar together are still detected")
    func dockAndMenuBarTogether() {
        let visibleFrame = visible(bottom: dockThickness, top: menuBarHeight, of: frame)
        #expect(DisplayGeometry.hostsSystemDock(frame: frame, visibleFrame: visibleFrame))
    }
}

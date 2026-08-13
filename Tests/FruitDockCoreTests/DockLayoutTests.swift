import Testing
@testable import FruitDockCore

@Suite("Dock layout")
struct DockLayoutTests {

    /// The built-in display: origin at zero, menu bar taken off the top.
    let builtIn = ScreenRect(x: 0, y: 0, width: 1512, height: 945)

    /// A second display to the right. Origin is not zero, which is the case
    /// that catches arithmetic written against a single screen.
    let toTheRight = ScreenRect(x: 1512, y: 0, width: 2560, height: 1440)

    /// A second display to the *left*, so its origin is negative. macOS allows
    /// this and it breaks anything that assumes coordinates start at zero.
    let toTheLeft = ScreenRect(x: -2560, y: 0, width: 2560, height: 1440)

    /// A display stacked above the primary.
    let above = ScreenRect(x: 0, y: 945, width: 1512, height: 945)

    let size = ScreenSize(width: 400, height: 70)
    let margin = DockLayout.defaultMargin

    // MARK: - Edges

    @Test("Bottom edge sits above the display's lower boundary, centred")
    func bottomEdge() {
        let frame = DockLayout.frame(for: size, edge: .bottom, in: builtIn)

        #expect(frame.minY == builtIn.minY + margin)
        #expect(frame.midX == builtIn.midX)
        #expect(frame.size == size)
    }

    @Test("Top edge sits below the display's upper boundary, centred")
    func topEdge() {
        let frame = DockLayout.frame(for: size, edge: .top, in: builtIn)

        #expect(frame.maxY == builtIn.maxY - margin)
        #expect(frame.midX == builtIn.midX)
    }

    @Test("Left edge sits inside the leading boundary, vertically centred")
    func leftEdge() {
        let frame = DockLayout.frame(for: size, edge: .left, in: builtIn)

        #expect(frame.minX == builtIn.minX + margin)
        #expect(frame.midY == builtIn.midY)
    }

    @Test("Right edge sits inside the trailing boundary, vertically centred")
    func rightEdge() {
        let frame = DockLayout.frame(for: size, edge: .right, in: builtIn)

        #expect(frame.maxX == builtIn.maxX - margin)
        #expect(frame.midY == builtIn.midY)
    }

    // MARK: - Displays that are not at the origin

    @Test("A dock on a second display lands on that display, not the primary")
    func secondDisplayIsNotTheOrigin() {
        let frame = DockLayout.frame(for: size, edge: .bottom, in: toTheRight)

        // Arithmetic written against a single screen would put this at x≈556,
        // on the built-in display, which is the bug this guards.
        #expect(frame.midX == toTheRight.midX)
        #expect(frame.minX > builtIn.maxX)
    }

    @Test("A display with a negative origin is handled")
    func negativeOriginDisplay() {
        let frame = DockLayout.frame(for: size, edge: .bottom, in: toTheLeft)

        #expect(frame.midX == toTheLeft.midX)
        #expect(frame.maxX < 0)
    }

    @Test("A display stacked above the primary is handled")
    func displayAbovePrimary() {
        let frame = DockLayout.frame(for: size, edge: .bottom, in: above)

        // Vertical arrangements are where coordinate errors hide: two
        // side-by-side displays of equal height make them invisible.
        #expect(frame.minY == above.minY + margin)
        #expect(frame.minY > builtIn.maxY - 1)
    }

    @Test("Every edge stays inside its display, on every arrangement")
    func alwaysWithinBounds() {
        for area in [builtIn, toTheRight, toTheLeft, above] {
            for edge in DockEdge.allCases {
                let frame = DockLayout.frame(for: size, edge: edge, in: area)

                #expect(frame.minX >= area.minX)
                #expect(frame.maxX <= area.maxX)
                #expect(frame.minY >= area.minY)
                #expect(frame.maxY <= area.maxY)
            }
        }
    }

    // MARK: - Clamping

    @Test("A dock wider than its display is clamped to fit")
    func oversizedDockIsClamped() {
        // Reachable with enough pinned apps on a small display; unclamped it
        // would run off the side or spill onto a neighbouring screen.
        let huge = ScreenSize(width: 5000, height: 70)

        let frame = DockLayout.frame(for: huge, edge: .bottom, in: builtIn)

        #expect(frame.size.width == builtIn.size.width)
        #expect(frame.minX >= builtIn.minX)
        #expect(frame.maxX <= builtIn.maxX)
    }

    @Test("A vertical dock taller than its display is clamped to fit")
    func oversizedVerticalDockIsClamped() {
        let huge = ScreenSize(width: 70, height: 5000)

        let frame = DockLayout.frame(for: huge, edge: .left, in: builtIn)

        #expect(frame.size.height == builtIn.size.height)
        #expect(frame.minY >= builtIn.minY)
        #expect(frame.maxY <= builtIn.maxY)
    }

    @Test("A custom margin is respected")
    func customMargin() {
        let frame = DockLayout.frame(for: size, edge: .bottom, in: builtIn, margin: 40)
        #expect(frame.minY == builtIn.minY + 40)
    }

    @Test("A zero margin flushes the dock against the edge")
    func zeroMargin() {
        let frame = DockLayout.frame(for: size, edge: .bottom, in: builtIn, margin: 0)
        #expect(frame.minY == builtIn.minY)
    }
}

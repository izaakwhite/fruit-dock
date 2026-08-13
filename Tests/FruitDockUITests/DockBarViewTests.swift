import AppKit
import Testing
@testable import FruitDockUI
import FruitDockCore

/// `DockBarView.size(for:isVertical:)` is pure geometry — no window, no
/// layer, no display required — so it is covered directly rather than
/// through the view it sizes.
///
/// Expected sizes are hand-computed from the constants the function itself
/// exposes (`iconSize`, `spacing`, `padding`, `indicatorLane`,
/// `separatorExtent`), not duplicated as a second copy of the arithmetic.
@MainActor
@Suite("Dock bar sizing")
struct DockBarViewTests {

    private let app = ApplicationInfo(
        bundleIdentifier: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app")

    private func entry() -> DockElement {
        .app(DockEntry(application: app, isPinned: false, isRunning: false))
    }

    private var breadth: CGFloat {
        DockBarView.padding * 2 + DockBarView.defaultIconSize + DockBarView.indicatorLane
    }

    @Test("An empty dock is one icon square, in either orientation")
    func emptyDockIsIconSquare() {
        let expected = NSSize(width: DockBarView.defaultIconSize, height: DockBarView.defaultIconSize)

        #expect(DockBarView.size(for: [], isVertical: false) == expected)
        #expect(DockBarView.size(for: [], isVertical: true) == expected)
    }

    @Test("A single icon's run is padding plus one icon, no spacing added")
    func singleElementHasNoInterElementSpacing() {
        let run = DockBarView.padding * 2 + DockBarView.defaultIconSize
        let size = DockBarView.size(for: [.trash], isVertical: false)

        #expect(size == NSSize(width: run, height: breadth))
    }

    @Test("Horizontal orientation puts the run on width and the fixed breadth on height")
    func horizontalPutsRunOnWidth() {
        let elements = [entry(), entry(), .separator, .trash]
        let run = DockBarView.padding * 2
            + DockBarView.defaultIconSize * 3
            + DockBarView.separatorExtent
            + CGFloat(elements.count - 1) * DockBarView.spacing

        let size = DockBarView.size(for: elements, isVertical: false)

        #expect(size == NSSize(width: run, height: breadth))
    }

    @Test("Vertical orientation puts the run on height and the fixed breadth on width")
    func verticalPutsRunOnHeight() {
        let elements = [entry(), .separator, entry()]
        let run = DockBarView.padding * 2
            + DockBarView.defaultIconSize * 2
            + DockBarView.separatorExtent
            + CGFloat(elements.count - 1) * DockBarView.spacing

        let size = DockBarView.size(for: elements, isVertical: true)

        #expect(size == NSSize(width: breadth, height: run))
    }

    @Test("Two apps and a trailing separator size to the literal constants, by hand")
    func literalSizeMatchesHandComputation() {
        // 8pt padding each side + two 48pt icons + one 11pt separator +
        // two 6pt gaps between the three elements = 16 + 96 + 11 + 12 = 135.
        // Breadth is 8pt padding each side + 48pt icon + 7pt indicator lane = 71.
        let size = DockBarView.size(for: [entry(), entry(), .separator], isVertical: false)

        #expect(size == NSSize(width: 135, height: 71))
    }

    @Test("A separator is narrower than an icon, and the run reflects that")
    func separatorIsNarrowerThanIcon() {
        let allIcons = DockBarView.size(for: [.trash, .trash], isVertical: false)
        let withSeparator = DockBarView.size(for: [.trash, .separator], isVertical: false)

        #expect(withSeparator.width < allIcons.width)
    }
}

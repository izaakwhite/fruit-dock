import Testing
@testable import FruitDockCore

@Suite("Dock magnification")
struct DockMagnificationTests {

    let maximum = 1.5

    // MARK: - The curve

    @Test("The tile under the cursor grows the most")
    func hoveredTileIsLargest() {
        #expect(DockMagnification.scale(distance: 0, maximum: maximum) == maximum)
    }

    @Test("Neighbours grow too, by less")
    func neighboursGrow() {
        // The distinguishing behaviour. Scaling only the hovered tile reads as
        // a different interaction, because the eye reads the shape of the run
        // rather than any single tile.
        let near = DockMagnification.scale(distance: 1, maximum: maximum)
        let far = DockMagnification.scale(distance: 2, maximum: maximum)

        #expect(near > 1)
        #expect(far > 1)
        #expect(near > far)
    }

    @Test("Tiles beyond the effect's reach stay at rest")
    func beyondInfluenceIsUnscaled() {
        #expect(DockMagnification.scale(distance: 2.5, maximum: maximum) == 1)
        #expect(DockMagnification.scale(distance: 9, maximum: maximum) == 1)
    }

    @Test("The curve is symmetric about the cursor")
    func symmetric() {
        for d in [0.5, 1.0, 1.7, 2.4] {
            #expect(
                DockMagnification.scale(distance: d, maximum: maximum)
                    == DockMagnification.scale(distance: -d, maximum: maximum))
        }
    }

    @Test("The curve reaches rest smoothly rather than stepping")
    func noStepAtTheEdge() {
        // A linear ramp leaves a visible crease at the cursor and an abrupt
        // stop at the edge, which is what makes a magnification look
        // mechanical. Just inside the boundary the scale must be very close to
        // rest.
        let edge = DockMagnification.scale(distance: 2.49, maximum: maximum)

        #expect(edge > 1)
        #expect(edge < 1.01)
    }

    @Test("Scaling is monotonic with distance")
    func monotonic() {
        let scales = stride(from: 0.0, through: 2.5, by: 0.25).map {
            DockMagnification.scale(distance: $0, maximum: maximum)
        }
        #expect(scales == scales.sorted(by: >))
    }

    // MARK: - Degenerate settings

    @Test("A maximum of 1 disables magnification")
    func disabledByMaximum() {
        #expect(DockMagnification.scale(distance: 0, maximum: 1) == 1)
    }

    @Test("A maximum below 1 never shrinks a tile")
    func backwardsMaximumDoesNotShrink() {
        // Reachable and observed: `largesize` can be configured below
        // `tilesize`. The answer is to leave tiles alone, not to shrink them.
        #expect(DockMagnification.scale(distance: 0, maximum: 0.5) == 1)
    }

    @Test("Zero influence disables magnification rather than dividing by zero")
    func zeroInfluence() {
        #expect(DockMagnification.scale(distance: 0, maximum: maximum, influence: 0) == 1)
    }

    // MARK: - Whole runs

    @Test("With no cursor every tile is at rest")
    func noCursorMeansNoMagnification() {
        let scales = DockMagnification.scales(count: 5, cursor: nil, maximum: maximum)
        #expect(scales == [1, 1, 1, 1, 1])
    }

    @Test("The peak follows the cursor along the run")
    func peakFollowsCursor() {
        for target in 0..<5 {
            let scales = DockMagnification.scales(
                count: 5, cursor: Double(target), maximum: maximum)
            let peak = scales.firstIndex(of: scales.max()!)

            #expect(peak == target)
        }
    }

    @Test("A cursor between two tiles raises both equally")
    func cursorBetweenTiles() {
        // The usual case — the pointer is rarely centred on a tile.
        let scales = DockMagnification.scales(count: 4, cursor: 1.5, maximum: maximum)

        #expect(abs(scales[1] - scales[2]) < 0.0001)
        #expect(scales[1] > scales[0])
    }

    @Test("An empty dock produces no scales")
    func emptyRun() {
        #expect(DockMagnification.scales(count: 0, cursor: 0, maximum: maximum).isEmpty)
    }

    // MARK: - Redistribution

    @Test("Tiles do not overlap once their neighbours have grown")
    func centresDoNotOverlap() {
        // Without redistributing, a magnified tile grows into the one beside it.
        let scales = DockMagnification.scales(count: 7, cursor: 3, maximum: maximum)
        let centres = DockMagnification.centres(scales: scales, tileSize: 48, spacing: 6)

        for i in 1..<centres.count {
            let gap = centres[i] - centres[i-1]
            let halves = (48 * scales[i] + 48 * scales[i-1]) / 2

            #expect(gap >= halves - 0.001)
        }
    }

    @Test("A run at rest keeps its resting centres")
    func restingCentresAreUnchanged() {
        let scales = DockMagnification.scales(count: 5, cursor: nil, maximum: maximum)
        let centres = DockMagnification.centres(scales: scales, tileSize: 48, spacing: 6)

        for (index, centre) in centres.enumerated() {
            #expect(abs(centre - (24 + Double(index) * 54)) < 0.001)
        }
    }

    @Test("Magnifying grows the run outward rather than pushing it sideways")
    func runStaysCentred() {
        // Laid out naively the run drifts along its axis as it grows, which
        // reads as the whole dock sliding under the pointer.
        let resting = DockMagnification.centres(
            scales: DockMagnification.scales(count: 9, cursor: nil, maximum: maximum),
            tileSize: 48, spacing: 6)
        let magnified = DockMagnification.centres(
            scales: DockMagnification.scales(count: 9, cursor: 4, maximum: maximum),
            tileSize: 48, spacing: 6)

        // Hovering the middle tile: its centre should barely move, while the
        // ends move outward in opposite directions.
        #expect(abs(magnified[4] - resting[4]) < 0.001)
        #expect(magnified[0] < resting[0])
        #expect(magnified[8] > resting[8])
    }

    @Test("A magnified run is longer than a resting one")
    func magnifiedRunIsLonger() {
        let resting = DockMagnification.length(
            scales: Array(repeating: 1, count: 6), tileSize: 48, spacing: 6)
        let magnified = DockMagnification.length(
            scales: DockMagnification.scales(count: 6, cursor: 2, maximum: maximum),
            tileSize: 48, spacing: 6)

        #expect(magnified > resting)
    }

    // MARK: - Reading the user's settings

    @Test("The maximum comes from the user's own Dock settings")
    func maximumFromSettings() {
        // largesize 96 against tilesize 48 is a doubling.
        #expect(
            DockMagnification.maximumScale(largeSize: 96, tileSize: 48, isEnabled: true) == 2)
    }

    @Test("Magnification switched off yields no scaling")
    func disabledInSettings() {
        #expect(
            DockMagnification.maximumScale(largeSize: 96, tileSize: 48, isEnabled: false) == 1)
    }

    @Test("A largesize below tilesize yields no scaling")
    func invertedSettingsYieldNoScaling() {
        // Exactly the configuration measured on the machine this was written
        // for: tilesize 66, largesize 58. Honouring it literally would shrink
        // tiles on hover, which no Dock does.
        #expect(
            DockMagnification.maximumScale(largeSize: 58, tileSize: 66, isEnabled: true) == 1)
    }

    @Test("An unset largesize yields no scaling")
    func absentLargeSize() {
        #expect(
            DockMagnification.maximumScale(largeSize: nil, tileSize: 48, isEnabled: true) == 1)
    }
}

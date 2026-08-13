import Testing
@testable import FruitDockCore

@Suite("Dock sizing")
struct DockSizingTests {

    let base = 48.0

    @Test("A display at the reference height uses the configured size unchanged")
    func referenceDisplayIsUnscaled() {
        #expect(DockSizing.iconSize(base: base, displayHeight: 1080) == base)
    }

    @Test("A larger display gets larger icons")
    func largerDisplayScalesUp() {
        let external = DockSizing.iconSize(base: base, displayHeight: 1440)
        #expect(external > base)
    }

    @Test("A smaller display gets smaller icons")
    func smallerDisplayScalesDown() {
        let laptop = DockSizing.iconSize(base: base, displayHeight: 900)
        #expect(laptop < base)
    }

    @Test("Scaling is damped rather than proportional")
    func scalingIsDamped() {
        // A display of twice the height gets icons half again as large, not
        // twice as large: sitting in front of a bigger monitor is not the same
        // as sitting twice as far from it.
        let doubled = DockSizing.iconSize(base: base, displayHeight: 2160)

        #expect(doubled == 72)
        #expect(doubled < base * 2)
    }

    @Test("Icons never fall below the minimum")
    func clampedAtMinimum() {
        // Reachable while a display is being reconfigured, when it can report
        // an implausibly small height for a moment.
        let tiny = DockSizing.iconSize(base: base, displayHeight: 1)
        #expect(tiny == DockSizing.minimumIconSize)
    }

    @Test("Icons never exceed the maximum")
    func clampedAtMaximum() {
        let vast = DockSizing.iconSize(base: base, displayHeight: 20_000)
        #expect(vast == DockSizing.maximumIconSize)
    }

    @Test("A zero or negative height falls back to the configured size")
    func degenerateHeightsFallBack() {
        // Never a divide by zero, and never an icon of no size at all.
        for height in [0.0, -1080.0] {
            #expect(DockSizing.iconSize(base: base, displayHeight: height) == base)
        }
    }

    @Test("A degenerate configured size is still clamped into range")
    func degenerateBaseIsClamped() {
        #expect(DockSizing.iconSize(base: 0, displayHeight: 1080) == DockSizing.minimumIconSize)
    }

    @Test("The result is always a whole number of points")
    func alwaysWholePoints() {
        // A fractional size renders blurry where the backing scale does not
        // divide it evenly.
        for height in [900.0, 945.0, 1080.0, 1440.0, 1600.0, 2160.0] {
            let size = DockSizing.iconSize(base: base, displayHeight: height)
            #expect(size == size.rounded())
        }
    }

    @Test("Larger displays never produce smaller icons")
    func monotonic() {
        let heights = [600.0, 900.0, 1080.0, 1440.0, 2160.0, 4320.0]
        let sizes = heights.map { DockSizing.iconSize(base: base, displayHeight: $0) }

        #expect(sizes == sizes.sorted())
    }

    // MARK: - Fitting the display

    /// The two displays this was written against, which is why the
    /// height-only rule was not enough: ten inches apart physically, 180
    /// points apart logically.
    let laptopWidth = 1440.0
    let laptopHeight = 900.0
    let externalWidth = 1920.0
    let externalHeight = 1080.0

    @Test("A dock that fits keeps the size the display asked for")
    func fittingDockIsUnchanged() {
        let preferred = DockSizing.iconSize(base: 66, displayHeight: externalHeight)

        let fitted = DockSizing.iconSize(
            base: 66, displayHeight: externalHeight,
            tileCount: 6, availableLength: externalWidth)

        #expect(fitted == preferred)
    }

    @Test("A dock too long for its display is shrunk to fit")
    func oversizedDockShrinks() {
        // Twenty apps at 66pt need more than a 13-inch laptop has to give.
        // Without this they were clamped to the screen's width by DockLayout,
        // which squeezes the tiles rather than sizing them.
        let fitted = DockSizing.iconSize(
            base: 66, displayHeight: laptopHeight,
            tileCount: 20, availableLength: laptopWidth)

        #expect(fitted < 66)

        let length = DockMetrics.default.length(tileCount: 20, iconSize: fitted)
        #expect(length <= laptopWidth * DockSizing.maximumLengthFraction)
    }

    @Test("The same dock is larger on the roomier display")
    func sameDockDiffersByDisplay() {
        // The point of the feature, and what the height-only rule failed to
        // deliver: 900 against 1080 damps to a difference of a few points.
        let laptop = DockSizing.iconSize(
            base: 66, displayHeight: laptopHeight,
            tileCount: 20, availableLength: laptopWidth)
        let external = DockSizing.iconSize(
            base: 66, displayHeight: externalHeight,
            tileCount: 20, availableLength: externalWidth)

        #expect(laptop < external)
    }

    @Test("Adding apps shrinks the icons rather than overflowing")
    func moreAppsMeansSmallerIcons() {
        let sizes = [4, 12, 20, 30, 40].map { count in
            DockSizing.iconSize(
                base: 66, displayHeight: laptopHeight,
                tileCount: count, availableLength: laptopWidth)
        }

        #expect(sizes == sizes.sorted(by: >))
    }

    @Test("The dock never exceeds its share of the display, at any count")
    func neverExceedsBudget() {
        let budget = laptopWidth * DockSizing.maximumLengthFraction

        for count in 1...60 {
            let size = DockSizing.iconSize(
                base: 66, displayHeight: laptopHeight,
                tileCount: count, availableLength: laptopWidth)
            let length = DockMetrics.default.length(tileCount: count, iconSize: size)

            // Below the minimum icon size the dock cannot shrink further —
            // clipping is preferable to icons too small to hit.
            if size > DockSizing.minimumIconSize {
                #expect(length <= budget)
            }
        }
    }

    @Test("The fitted size is the largest that fits, not merely one that does")
    func fittedSizeIsMaximal() {
        // Every other fitting test here passed while the calculation shrank
        // docks by a whole tile more than necessary, because they all asked
        // whether it fits and none asked whether it could have been bigger.
        let preferred = DockSizing.iconSize(base: 66, displayHeight: laptopHeight)

        for count in [8, 20, 35] {
            let size = DockSizing.iconSize(
                base: 66, displayHeight: laptopHeight,
                tileCount: count, availableLength: laptopWidth)

            // Only meaningful where fitting actually bit. A dock small enough
            // to keep the size its display asked for is capped by preference,
            // not by the budget, and has no larger size to have missed.
            guard size < preferred, size > DockSizing.minimumIconSize else { continue }

            let budget = laptopWidth * DockSizing.maximumLengthFraction
            let oneLarger = DockMetrics.default.length(
                tileCount: count, iconSize: size + 1)

            #expect(oneLarger > budget)
        }
    }

    @Test("Separators are counted against the budget")
    func separatorsTakeRoom() {
        let without = DockSizing.iconSize(
            base: 66, displayHeight: laptopHeight,
            tileCount: 20, separatorCount: 0, availableLength: laptopWidth)
        let with = DockSizing.iconSize(
            base: 66, displayHeight: laptopHeight,
            tileCount: 20, separatorCount: 3, availableLength: laptopWidth)

        #expect(with <= without)
    }

    @Test("Icons never shrink below the minimum, however many there are")
    func crowdedDockStopsAtMinimum() {
        // Two hundred apps cannot fit legibly. Tiles too small to click are
        // worse than a dock that overflows.
        let size = DockSizing.iconSize(
            base: 66, displayHeight: laptopHeight,
            tileCount: 200, availableLength: laptopWidth)

        #expect(size == DockSizing.minimumIconSize)
    }

    @Test("An empty dock and an unknown display fall back rather than divide")
    func degenerateFittingInputs() {
        let noTiles = DockSizing.iconSize(
            base: 66, displayHeight: laptopHeight, tileCount: 0, availableLength: laptopWidth)
        let noSpace = DockSizing.iconSize(
            base: 66, displayHeight: laptopHeight, tileCount: 10, availableLength: 0)

        #expect(noTiles == DockSizing.iconSize(base: 66, displayHeight: laptopHeight))
        #expect(noSpace == DockSizing.iconSize(base: 66, displayHeight: laptopHeight))
    }

    @Test("A vertical dock is fitted against the display's height")
    func verticalDockUsesHeight() {
        // The long axis is the one that has to fit, and for a dock on the left
        // or right edge that is the height.
        let size = DockSizing.iconSize(
            base: 66, displayHeight: laptopHeight,
            tileCount: 20, availableLength: laptopHeight)

        let length = DockMetrics.default.length(tileCount: 20, iconSize: size)
        #expect(length <= laptopHeight * DockSizing.maximumLengthFraction)
    }

    // MARK: - Inheriting the system Dock's size

    @Test("The system Dock's icon size is adopted as the base")
    func adoptsSystemTileSize() {
        // Someone who enlarged their Dock wanted larger icons. Starting from a
        // constant instead produces a dock that sits beside theirs at a
        // visibly different size.
        #expect(SystemDockPreferences.tileSize(66) == 66)
    }

    @Test("An untouched Dock size falls back to Apple's default")
    func absentTileSizeUsesDefault() {
        // The key is absent on any Mac where the slider was never moved.
        #expect(
            SystemDockPreferences.tileSize(nil) == SystemDockPreferences.defaultTileSize)
    }

    @Test("A size outside Apple's own slider range is clamped")
    func implausibleTileSizeIsClamped() {
        // Outside that range it did not come from the slider, so it is more
        // likely a stale or corrupt key than an instruction worth honouring.
        #expect(SystemDockPreferences.tileSize(4) == SystemDockPreferences.tileSizeRange.lowerBound)
        #expect(SystemDockPreferences.tileSize(999) == SystemDockPreferences.tileSizeRange.upperBound)
    }

    @Test("A non-finite size falls back rather than propagating")
    func nonFiniteTileSizeFallsBack() {
        // A NaN would survive every comparison below and reach Auto Layout,
        // which reacts to it far less gracefully than a fallback does.
        #expect(
            SystemDockPreferences.tileSize(.nan) == SystemDockPreferences.defaultTileSize)
        #expect(
            SystemDockPreferences.tileSize(.infinity)
                == SystemDockPreferences.defaultTileSize)
    }

    @Test("A real two-display arrangement gets two different sizes")
    func laptopAndExternalDiffer() {
        // The case that prompted this: a 14-inch MacBook Pro beside a 1440p
        // external, where one fixed size cannot suit both.
        let builtIn = DockSizing.iconSize(base: base, displayHeight: 945)
        let external = DockSizing.iconSize(base: base, displayHeight: 1440)

        #expect(builtIn < external)
        #expect(builtIn >= DockSizing.minimumIconSize)
        #expect(external <= DockSizing.maximumIconSize)
    }
}

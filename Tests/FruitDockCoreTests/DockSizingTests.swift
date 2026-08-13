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

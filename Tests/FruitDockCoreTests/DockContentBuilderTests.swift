import Testing
@testable import FruitDockCore

@Suite("Dock contents")
struct DockContentBuilderTests {

    let safari = ApplicationInfo(
        bundleIdentifier: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app")
    let terminal = ApplicationInfo(
        bundleIdentifier: "com.apple.Terminal", name: "Terminal", path: "/System/Applications/Utilities/Terminal.app")
    let notes = ApplicationInfo(
        bundleIdentifier: "com.apple.Notes", name: "Notes", path: "/System/Applications/Notes.app")

    @Test("A pinned app shows even when it is not running")
    func pinnedAppShowsWhenNotRunning() {
        let entries = DockContentBuilder.entries(
            pinned: [DockItem(safari)],
            running: [],
            showsRunningApps: true
        )

        #expect(entries.count == 1)
        #expect(entries[0].application == safari)
        #expect(entries[0].isPinned)
        #expect(!entries[0].isRunning)
    }

    @Test("A pinned app that is running gets a running indicator — FR-3.3")
    func pinnedRunningAppIsMarkedRunning() {
        let entries = DockContentBuilder.entries(
            pinned: [DockItem(safari)],
            running: [safari],
            showsRunningApps: true
        )

        #expect(entries.count == 1)
        #expect(entries[0].isRunning)
    }

    @Test("An app that is both pinned and running appears exactly once")
    func noDuplicateWhenPinnedAndRunning() {
        let entries = DockContentBuilder.entries(
            pinned: [DockItem(safari)],
            running: [safari, terminal],
            showsRunningApps: true
        )

        let safariEntries = entries.filter { $0.application == safari }
        #expect(safariEntries.count == 1)
        #expect(entries.count == 2)
    }

    @Test("Unpinned running apps follow the pinned ones — FR-3.4")
    func runningAppsComeAfterPinned() {
        let entries = DockContentBuilder.entries(
            pinned: [DockItem(safari), DockItem(notes)],
            running: [terminal],
            showsRunningApps: true
        )

        #expect(entries.map(\.application) == [safari, notes, terminal])
        #expect(entries.last?.isPinned == false)
    }

    @Test("Disabling running apps hides unpinned ones")
    func runningAppsHiddenWhenDisabled() {
        let entries = DockContentBuilder.entries(
            pinned: [DockItem(safari)],
            running: [safari, terminal, notes],
            showsRunningApps: false
        )

        #expect(entries.count == 1)
        #expect(entries[0].application == safari)
        // Pinned apps still report running state when the section is off.
        #expect(entries[0].isRunning)
    }

    @Test("Pinned order is preserved exactly")
    func pinnedOrderIsStable() {
        // A dock that reorders itself between launches is unusable, so this
        // is load-bearing rather than cosmetic.
        let pinned = [DockItem(notes), DockItem(safari), DockItem(terminal)]

        let entries = DockContentBuilder.entries(
            pinned: pinned,
            running: [terminal, safari],
            showsRunningApps: true
        )

        #expect(entries.map(\.application.bundleIdentifier) == pinned.map(\.bundleIdentifier))
    }

    @Test("An empty dock is representable")
    func emptyDock() {
        let entries = DockContentBuilder.entries(
            pinned: [], running: [], showsRunningApps: true)

        #expect(entries.isEmpty)
    }
}

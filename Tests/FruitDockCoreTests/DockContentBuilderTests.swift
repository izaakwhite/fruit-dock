import Testing
@testable import FruitDockCore

@Suite("Dock contents")
struct DockContentBuilderTests {

    let finder = ApplicationInfo(
        bundleIdentifier: "com.apple.finder", name: "Finder", path: "/System/Library/CoreServices/Finder.app")
    let safari = ApplicationInfo(
        bundleIdentifier: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app")
    let terminal = ApplicationInfo(
        bundleIdentifier: "com.apple.Terminal", name: "Terminal", path: "/System/Applications/Utilities/Terminal.app")
    let notes = ApplicationInfo(
        bundleIdentifier: "com.apple.Notes", name: "Notes", path: "/System/Applications/Notes.app")

    /// Applications only, in order — the part most assertions care about.
    private func apps(_ elements: [DockElement]) -> [ApplicationInfo] {
        elements.compactMap(\.entry?.application)
    }

    // MARK: - Applications

    @Test("A pinned app shows even when it is not running")
    func pinnedAppShowsWhenNotRunning() {
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari)], running: [], showsRunningApps: true)

        #expect(apps(elements) == [safari])
        #expect(elements.first?.entry?.isRunning == false)
    }

    @Test("A pinned app that is running gets a running indicator — FR-3.3")
    func pinnedRunningAppIsMarkedRunning() {
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari)], running: [safari], showsRunningApps: true)

        #expect(elements.first?.entry?.isRunning == true)
    }

    @Test("An app that is both pinned and running appears exactly once")
    func noDuplicateWhenPinnedAndRunning() {
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari)], running: [safari, terminal], showsRunningApps: true)

        #expect(apps(elements).filter { $0 == safari }.count == 1)
        #expect(apps(elements) == [safari, terminal])
    }

    @Test("Unpinned running apps follow the pinned ones — FR-3.4")
    func runningAppsComeAfterPinned() {
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari), DockItem(notes)],
            running: [terminal],
            showsRunningApps: true
        )

        #expect(apps(elements) == [safari, notes, terminal])
        #expect(elements.compactMap(\.entry).last?.isPinned == false)
    }

    @Test("Disabling running apps hides unpinned ones")
    func runningAppsHiddenWhenDisabled() {
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari)],
            running: [safari, terminal, notes],
            showsRunningApps: false
        )

        #expect(apps(elements) == [safari])
        // Pinned apps still report running state when the section is off.
        #expect(elements.first?.entry?.isRunning == true)
    }

    @Test("Pinned order is preserved exactly")
    func pinnedOrderIsStable() {
        // A dock that reorders itself between launches is unusable, so this
        // is load-bearing rather than cosmetic.
        let pinned = [DockItem(notes), DockItem(safari), DockItem(terminal)]

        let elements = DockContentBuilder.elements(
            pinned: pinned, running: [terminal, safari], showsRunningApps: true)

        #expect(apps(elements).map(\.bundleIdentifier) == pinned.map(\.bundleIdentifier))
    }

    // MARK: - Finder anchoring

    @Test("Finder is anchored first, ahead of pinned apps")
    func finderComesFirst() {
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari), DockItem(notes)],
            running: [finder],
            showsRunningApps: true
        )

        #expect(apps(elements).first == finder)
    }

    @Test("Finder appears once even when pinned and running")
    func finderIsNotDuplicated() {
        // Finder can arrive from three directions at once — anchored, pinned,
        // and running — so deduplication has to survive all three.
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(finder), DockItem(safari)],
            running: [finder, safari],
            showsRunningApps: true
        )

        #expect(apps(elements).filter { $0 == finder }.count == 1)
        #expect(apps(elements) == [finder, safari])
    }

    @Test("Finder is not invented when the system does not report it")
    func finderAbsentWhenUnknown() {
        // Its real path is unknowable without the system telling us, and a
        // fabricated one would render a broken icon.
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari)], running: [safari], showsRunningApps: true)

        #expect(!apps(elements).contains(finder))
    }

    // MARK: - Recent apps

    @Test("Recent apps form their own section after the running ones")
    func recentsFollowRunningBehindSeparator() {
        // A tile the user never chose must not read as one they did, so the
        // section is divided rather than merged into the run of icons.
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari)],
            running: [terminal],
            recents: [notes],
            showsRunningApps: true,
            showsRecentApps: true,
            showsTrash: false
        )

        #expect(apps(elements) == [safari, terminal, notes])
        #expect(elements[2] == .separator)
        // Recents are not pinned, whatever else they are.
        #expect(elements.last?.entry?.isPinned == false)
    }

    @Test("A recent app that is already pinned is not shown twice")
    func recentAlreadyPinnedIsSkipped() {
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari)],
            running: [],
            recents: [safari, notes],
            showsRunningApps: true,
            showsRecentApps: true
        )

        #expect(apps(elements) == [safari, notes])
    }

    @Test("A recent app that is running is not shown twice")
    func recentAlreadyRunningIsSkipped() {
        let elements = DockContentBuilder.elements(
            pinned: [],
            running: [terminal],
            recents: [terminal],
            showsRunningApps: true,
            showsRecentApps: true,
            showsTrash: false
        )

        #expect(apps(elements) == [terminal])
        #expect(!elements.contains(.separator))
    }

    @Test("The same app listed twice in recents appears once")
    func duplicateRecentsCollapse() {
        let elements = DockContentBuilder.elements(
            pinned: [], running: [], recents: [notes, notes],
            showsRunningApps: true, showsRecentApps: true, showsTrash: false)

        #expect(apps(elements) == [notes])
    }

    @Test("A recent app that is running still gets a running indicator")
    func recentRunningAppIsMarkedRunning() {
        // Reachable when the running section is off: the app is running, and
        // an indicator that lied about it would be worse than no section.
        let elements = DockContentBuilder.elements(
            pinned: [], running: [terminal], recents: [terminal],
            showsRunningApps: false, showsRecentApps: true)

        #expect(elements.first?.entry?.isRunning == true)
    }

    @Test("Recents are hidden when the section is switched off")
    func recentsHiddenWhenDisabled() {
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari)], running: [], recents: [notes],
            showsRunningApps: true, showsRecentApps: false, showsTrash: false)

        #expect(apps(elements) == [safari])
        #expect(!elements.contains(.separator))
    }

    @Test("An empty recents list draws no separator")
    func emptyRecentsDrawNoSeparator() {
        // A divider with nothing after it is a stray line, which is what a Mac
        // with no recent apps would otherwise get.
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari)], running: [], recents: [],
            showsRunningApps: true, showsRecentApps: true, showsTrash: false)

        #expect(elements == [.app(DockEntry(application: safari, isPinned: true, isRunning: false))])
    }

    @Test("Recents on an otherwise empty dock draw no leading separator")
    func recentsOnEmptyDockDrawNoLeadingSeparator() {
        let elements = DockContentBuilder.elements(
            pinned: [], running: [], recents: [notes],
            showsRunningApps: true, showsRecentApps: true, showsTrash: false)

        #expect(elements == [.app(DockEntry(application: notes, isPinned: false, isRunning: false))])
    }

    // MARK: - Separator and Trash

    @Test("Trash is last, behind a separator")
    func trashIsLastBehindSeparator() {
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari)], running: [], showsRunningApps: true)

        #expect(elements.last == .trash)
        #expect(elements.dropLast().last == .separator)
    }

    @Test("Trash and its separator can be hidden together")
    func trashCanBeHidden() {
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(safari)], running: [], showsRunningApps: true, showsTrash: false)

        #expect(!elements.contains(.trash))
        // A separator with nothing after it would be a stray line.
        #expect(!elements.contains(.separator))
    }

    @Test("An empty dock shows Trash without a separator above it")
    func emptyDockKeepsTrash() {
        // A separator needs something on both sides. With nothing pinned or
        // running it is a line floating above a single tile — the same stray
        // line the recents section already avoids, which this case used to
        // draw anyway.
        let elements = DockContentBuilder.elements(
            pinned: [], running: [], showsRunningApps: true)

        #expect(elements == [.trash])
    }

    @Test("A dock with nothing at all is representable")
    func fullyEmptyDock() {
        let elements = DockContentBuilder.elements(
            pinned: [], running: [], showsRunningApps: true, showsTrash: false)

        #expect(elements.isEmpty)
    }
}

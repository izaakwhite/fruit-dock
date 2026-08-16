import Testing
@testable import FruitDockCore

@Suite("Minimised windows")
@MainActor
struct MinimizedWindowTests {

    func window(_ title: String, _ application: ApplicationInfo, index: Int = 0) -> WindowTile {
        WindowTile(
            title: title, application: application,
            processIdentifier: 501, windowIndex: index)
    }

    @Test("Minimised windows share the last section with Trash")
    func minimizedWindowsFormTheirOwnSection() {
        let tile = window("Report.pages", Fixture.safari)

        let elements = DockContentBuilder.elements(
            pinned: [DockItem(Fixture.safari)],
            running: [],
            minimizedWindows: [tile],
            showsRunningApps: true,
            showsTrash: false
        )

        // Not applications: nothing to launch, nothing to quit, no running
        // state. The separator is what says so.
        #expect(elements[1] == .separator)
        #expect(elements[2] == .minimizedWindow(tile))
    }

    @Test("Folders come before minimised windows")
    func foldersPrecedeWindows() {
        let elements = DockContentBuilder.elements(
            pinned: [], running: [],
            folders: [Fixture.downloads],
            minimizedWindows: [window("Notes", Fixture.terminal)],
            showsRunningApps: true, showsTrash: true)

        #expect(elements.first == .folder(Fixture.downloads))
        #expect(elements.last == .trash)
    }

    @Test("Two windows of one app are distinct tiles")
    func windowsOfSameAppAreDistinct() {
        // Identity has to include the window, not just the process, or the
        // second tile replaces the first.
        let first = window("One", Fixture.safari, index: 0)
        let second = window("Two", Fixture.safari, index: 1)

        #expect(first.id != second.id)

        let elements = DockContentBuilder.elements(
            pinned: [], running: [], minimizedWindows: [first, second],
            showsRunningApps: true, showsTrash: false)

        #expect(elements.count == 2)
    }

    @Test("An untitled window still reads as something")
    func untitledWindowHasALabel() {
        // Common — a blank document, a palette. An empty label looks like a
        // rendering fault rather than an untitled window.
        #expect(window("", Fixture.safari).label == "Safari — Untitled")
    }

    @Test("A titled window shows its own title")
    func titledWindowUsesItsTitle() {
        #expect(window("Report.pages", Fixture.safari).label == "Report.pages")
    }

    @Test("No minimised windows means no section at all")
    func absentSectionWhenNone() {
        // Reading them needs Accessibility permission, so empty also means
        // "cannot see" — either way an empty section would be worse than none.
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(Fixture.safari)], running: [],
            minimizedWindows: [], showsRunningApps: true, showsTrash: false)

        #expect(elements.count == 1)
        #expect(elements.first?.entry?.application == Fixture.safari)
    }

    @Test("Restoring a window takes it off the dock")
    func restoringRemovesTheTile() {
        // Nothing else would notice: minimising is neither a launch nor a
        // termination, so the running-applications notification never fires and
        // the tile would otherwise outlive the window it stands for.
        let apps = FakeApplicationProvider([Fixture.safari])
        apps.minimizedWindows = [window("Report.pages", Fixture.safari)]

        let presenter = FakePresenter()
        let coordinator = DockCoordinator(
            displayProvider: FakeDisplayProvider([Fixture.builtIn]),
            applicationProvider: apps,
            systemDock: FakeSystemDock(),
            applicationCatalog: FakeApplicationCatalog(),
            store: FakeConfigurationStore(),
            presenter: presenter
        )
        coordinator.start()
        #expect(presenter.renderedElements.contains { if case .minimizedWindow = $0 { return true }; return false })

        coordinator.restore(apps.minimizedWindows[0])

        #expect(apps.restored.count == 1)
        #expect(!presenter.renderedElements.contains { if case .minimizedWindow = $0 { return true }; return false })
    }

    @Test("Opening a folder asks the system to reveal its path")
    func openingFolderForwardsPath() {
        let apps = FakeApplicationProvider()
        let coordinator = DockCoordinator(
            displayProvider: FakeDisplayProvider([Fixture.builtIn]),
            applicationProvider: apps,
            systemDock: FakeSystemDock(),
            applicationCatalog: FakeApplicationCatalog(),
            store: FakeConfigurationStore(),
            presenter: FakePresenter()
        )

        coordinator.open(Fixture.downloads)

        #expect(apps.openedFolders == [Fixture.downloads.path])
    }
}

import Testing
@testable import FruitDockCore

/// Parsing `persistent-others`, where Apple keeps pinned folders.
@MainActor
@Suite("Dock folders")
struct DockFolderTests {

    let downloads = DockFolder(name: "Downloads", path: "/Users/test/Downloads/")

    @Test("A directory tile becomes a folder")
    func parsesDirectoryTile() {
        let folders = SystemDockPreferences.folders(fromTiles: [Fixture.directoryTile(downloads)])

        #expect(folders.map(\.name) == ["Downloads"])
        // Normalised without the trailing slash the Dock writes, so that the
        // same folder cannot be pinned twice under two spellings of one path.
        #expect(folders.first?.path == "/Users/test/Downloads")
    }

    @Test("Display and view styles are read from the tile")
    func parsesStyles() {
        let folder = DockFolder(
            name: "Projects", path: "/Users/test/Projects/", displayAs: .folder, showAs: .grid)

        let parsed = SystemDockPreferences.folders(fromTiles: [Fixture.directoryTile(folder)]).first

        #expect(parsed?.displayAs == .folder)
        #expect(parsed?.showAs == .grid)
    }

    @Test("Absent styles fall back rather than failing the tile")
    func missingStylesFallBack() {
        // Older Docks, and tiles written by versions of macOS we have not seen.
        let tile: [String: Any] = [
            "tile-type": "directory-tile",
            "tile-data": [
                "file-label": "Documents",
                "file-data": ["_CFURLString": "file:///Users/test/Documents/"],
            ],
        ]

        let folder = SystemDockPreferences.folders(fromTiles: [tile]).first

        #expect(folder?.displayAs == .stack)
        #expect(folder?.showAs == .automatic)
    }

    @Test("Application tiles in the list are ignored")
    func skipsNonDirectoryTiles() {
        // `persistent-others` also carries pinned files and URLs, which are not
        // stacks and have nothing to open into.
        let tiles: [Any] = [Fixture.tile(Fixture.safari), Fixture.directoryTile(downloads)]

        #expect(SystemDockPreferences.folders(fromTiles: tiles).map(\.name) == ["Downloads"])
    }

    @Test("A deleted folder is skipped")
    func skipsMissingFolder() {
        // The Dock keeps a tile after its folder is gone, and a stack that
        // opens onto nothing is worse than no stack.
        let folders = SystemDockPreferences.folders(
            fromTiles: [Fixture.directoryTile(downloads)],
            exists: { _ in false }
        )

        #expect(folders.isEmpty)
    }

    @Test("A percent-encoded path is decoded")
    func decodesEncodedPath() {
        let spaced = DockFolder(name: "My Files", path: "/Users/test/My Files/")

        let parsed = SystemDockPreferences.folders(fromTiles: [Fixture.directoryTile(spaced)]).first

        // Undecoded, this path opens nothing at all.
        #expect(parsed?.path == "/Users/test/My Files")
    }

    @Test("A folder with no label is named from its path")
    func derivesNameFromPath() {
        // The trailing slash matters: taken naively the last component is
        // empty, and every folder would be nameless.
        let tile: [String: Any] = [
            "tile-type": "directory-tile",
            "tile-data": ["file-data": ["_CFURLString": "file:///Users/test/Downloads/"]],
        ]

        #expect(SystemDockPreferences.folders(fromTiles: [tile]).first?.name == "Downloads")
    }

    @Test("The same folder pinned twice appears once")
    func duplicatesCollapse() {
        let tiles = [Fixture.directoryTile(downloads), Fixture.directoryTile(downloads)]
        #expect(SystemDockPreferences.folders(fromTiles: tiles).count == 1)
    }

    @Test("Malformed tiles cost themselves and nothing else")
    func malformedTilesAreSkipped() {
        let tiles: [Any] = [
            "not a dictionary",
            ["tile-type": "directory-tile"],
            ["tile-type": "directory-tile", "tile-data": [String: Any]()],
            Fixture.directoryTile(downloads),
        ]

        #expect(SystemDockPreferences.folders(fromTiles: tiles).map(\.name) == ["Downloads"])
    }

    // MARK: - Placement

    @Test("Folders sit after the applications, behind a separator")
    func foldersFormTheirOwnSection() {
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(Fixture.safari)],
            running: [],
            folders: [downloads],
            showsRunningApps: true,
            showsTrash: false
        )

        #expect(elements.count == 3)
        #expect(elements[1] == .separator)
        #expect(elements[2] == .folder(downloads))
    }

    @Test("Folders come before the Trash")
    func foldersPrecedeTrash() {
        // Apple's Dock puts Trash last, after everything else in that section.
        let elements = DockContentBuilder.elements(
            pinned: [DockItem(Fixture.safari)], running: [],
            folders: [downloads], showsRunningApps: true)

        #expect(elements.last == .trash)
        #expect(elements.dropLast().last == .folder(downloads))
    }

    @Test("A dock of only folders draws no leading separator")
    func foldersWithoutAppsHaveNoSeparator() {
        let elements = DockContentBuilder.elements(
            pinned: [], running: [], folders: [downloads],
            showsRunningApps: true, showsTrash: false)

        #expect(elements == [.folder(downloads)])
    }
}

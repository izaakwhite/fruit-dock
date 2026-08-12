import Testing
@testable import FruitDockCore

/// Apple's Dock preferences are written by a process we do not control, on
/// versions of macOS we have not seen. Every one of these fixtures is a shape
/// that must not take the import down with it.
@Suite("System Dock preferences")
struct SystemDockPreferencesTests {

    /// A tile in the shape a real `com.apple.dock` stores, confirmed against a
    /// live plist on macOS 26.
    private func tile(
        identifier: String? = "com.apple.Safari",
        label: String? = "Safari",
        url: String? = "file:///Applications/Safari.app/"
    ) -> [String: Any] {
        var tileData: [String: Any] = ["dock-extra": 0, "file-type": 41]
        if let identifier { tileData["bundle-identifier"] = identifier }
        if let label { tileData["file-label"] = label }
        if let url { tileData["file-data"] = ["_CFURLString": url, "_CFURLStringType": 15] }

        return ["GUID": 666_512_219, "tile-type": "file-tile", "tile-data": tileData]
    }

    // MARK: - Well-formed tiles

    @Test("A Dock tile becomes the application it names")
    func tileBecomesApplication() {
        let applications = SystemDockPreferences.applications(fromTiles: [tile()])

        #expect(applications.count == 1)
        #expect(applications.first?.bundleIdentifier == "com.apple.Safari")
        #expect(applications.first?.name == "Safari")
        #expect(applications.first?.path == "/Applications/Safari.app")
    }

    @Test("A percent-encoded URL becomes a usable filesystem path")
    func percentEncodedPathIsDecoded() {
        // Every application with a space in its name arrives like this, and a
        // path left encoded launches nothing and draws no icon.
        let applications = SystemDockPreferences.applications(
            fromTiles: [tile(url: "file:///Applications/Prime%20Video.app/")])

        #expect(applications.first?.path == "/Applications/Prime Video.app")
    }

    @Test("Tiles keep the order Apple's Dock stored them in")
    func orderIsPreserved() {
        // Importing is only worth doing if it reproduces the arrangement the
        // user already made.
        let tiles = [
            tile(identifier: "com.apple.mail", label: "Mail", url: "file:///System/Applications/Mail.app/"),
            tile(),
            tile(identifier: "com.apple.Notes", label: "Notes", url: "file:///System/Applications/Notes.app/"),
        ]

        let applications = SystemDockPreferences.applications(fromTiles: tiles)

        #expect(applications.map(\.name) == ["Mail", "Safari", "Notes"])
    }

    @Test("An empty persistent-apps yields nothing rather than failing")
    func emptyTilesYieldNothing() {
        #expect(SystemDockPreferences.applications(fromTiles: []).isEmpty)
    }

    @Test("An application listed twice appears once")
    func duplicateTilesCollapse() {
        let applications = SystemDockPreferences.applications(fromTiles: [tile(), tile()])

        #expect(applications.count == 1)
    }

    // MARK: - Malformed tiles

    @Test("One malformed tile costs that tile, not the whole import")
    func malformedTileIsSkippedInIsolation() {
        let tiles: [Any] = [
            "not a dictionary at all",
            ["tile-data": "not a dictionary either"],
            tile(),
        ]

        let applications = SystemDockPreferences.applications(fromTiles: tiles)

        #expect(applications.map(\.name) == ["Safari"])
    }

    @Test("A tile with no tile-data is skipped")
    func tileWithoutTileDataIsSkipped() {
        let tiles: [Any] = [["GUID": 1, "tile-type": "file-tile"]]

        #expect(SystemDockPreferences.applications(fromTiles: tiles).isEmpty)
    }

    @Test("A tile with no file-data is skipped")
    func tileWithoutFileDataIsSkipped() {
        #expect(SystemDockPreferences.applications(fromTiles: [tile(url: nil)]).isEmpty)
    }

    @Test("A file-data with no _CFURLString is skipped")
    func tileWithoutURLStringIsSkipped() {
        let tiles: [Any] = [["tile-data": ["file-data": ["_CFURLStringType": 15]]]]

        #expect(SystemDockPreferences.applications(fromTiles: tiles).isEmpty)
    }

    @Test("A URL that is not a file URL is skipped")
    func nonFileURLIsSkipped() {
        // `URL` parses a bare string into a schemeless URL rather than
        // returning nil, so the scheme has to be checked explicitly or a
        // nonsense tile becomes a nonsense path.
        #expect(SystemDockPreferences.applications(fromTiles: [tile(url: "not a url")]).isEmpty)
        #expect(SystemDockPreferences.applications(
            fromTiles: [tile(url: "https://example.com/App.app")]).isEmpty)
    }

    // MARK: - Missing fields

    @Test("A tile with no file-label is named after its bundle")
    func nameFallsBackToBundleName() {
        let applications = SystemDockPreferences.applications(
            fromTiles: [tile(label: nil, url: "file:///Applications/Prime%20Video.app/")])

        #expect(applications.first?.name == "Prime Video")
    }

    @Test("An empty file-label is treated as no label at all")
    func emptyLabelFallsBack() {
        let applications = SystemDockPreferences.applications(fromTiles: [tile(label: "")])

        #expect(applications.first?.name == "Safari")
    }

    @Test("A tile with no bundle identifier falls back to its path")
    func identifierFallsBackToPath() {
        // Identity has to be unique and stable — pinning and deduplication key
        // on it — and a guess derived from the name could collide with a real
        // identifier. Launching works from the path either way.
        let applications = SystemDockPreferences.applications(fromTiles: [tile(identifier: nil)])

        #expect(applications.first?.bundleIdentifier == "/Applications/Safari.app")
    }

    @Test("An empty bundle identifier is treated as missing")
    func emptyIdentifierFallsBack() {
        let applications = SystemDockPreferences.applications(fromTiles: [tile(identifier: "")])

        #expect(applications.first?.bundleIdentifier == "/Applications/Safari.app")
    }

    // MARK: - Applications that are no longer installed

    @Test("A tile pointing at an application that has been deleted is dropped")
    func uninstalledApplicationIsDropped() {
        // The Dock keeps tiles for apps that are gone; importing one produces
        // an icon that cannot draw and a click that cannot launch.
        let tiles = [
            tile(),
            tile(identifier: "com.old.App", label: "Old", url: "file:///Applications/Old.app/"),
        ]

        let applications = SystemDockPreferences.applications(fromTiles: tiles) { path in
            path != "/Applications/Old.app"
        }

        #expect(applications.map(\.name) == ["Safari"])
    }

    @Test("Every tile pointing at something deleted leaves an empty import")
    func allUninstalledYieldsNothing() {
        let applications = SystemDockPreferences.applications(fromTiles: [tile()]) { _ in false }

        #expect(applications.isEmpty)
    }

    // MARK: - show-recents

    @Test("Recents default to on when the user has never set the preference")
    func recentsDefaultOnWhenUnset() {
        // The key is simply absent on a Mac where nobody touched the setting,
        // which is most of them — and absent means on, not off.
        #expect(SystemDockPreferences.showsRecentApplications(nil))
    }

    @Test("A user who turned recents off is honoured")
    func recentsOffIsHonoured() {
        #expect(!SystemDockPreferences.showsRecentApplications(false))
        #expect(SystemDockPreferences.showsRecentApplications(true))
    }
}

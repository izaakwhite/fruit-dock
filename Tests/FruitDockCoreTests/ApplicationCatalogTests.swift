import Testing
@testable import FruitDockCore

@Suite("Application catalog")
struct ApplicationCatalogTests {

    private func app(_ name: String, id: String? = nil) -> ApplicationInfo {
        ApplicationInfo(
            bundleIdentifier: id ?? "com.example.\(name)",
            name: name,
            path: "/Applications/\(name).app"
        )
    }

    @Test("Applications are filed under the initial of their name")
    func groupedByInitial() {
        let groups = ApplicationCatalog.groups(from: [app("Safari"), app("Notes"), app("Numbers")])

        #expect(groups.map(\.title) == ["N", "S"])
        #expect(groups.first?.applications.map(\.name) == ["Notes", "Numbers"])
    }

    @Test("A lowercase name is filed with its uppercase neighbours")
    func filingIsCaseInsensitive() {
        let groups = ApplicationCatalog.groups(from: [app("Slack"), app("iTerm"), app("Safari")])

        #expect(groups.map(\.title) == ["I", "S"])
        // Sorted as the user reads them, so "iTerm" is not exiled below "Zoom".
        #expect(groups.last?.applications.map(\.name) == ["Safari", "Slack"])
    }

    @Test("A name starting with a digit or symbol is filed under #, after the letters")
    func nonLettersAreFiledUnderSymbol() {
        let groups = ApplicationCatalog.groups(from: [app("1Password"), app("Safari")])

        #expect(groups.map(\.title) == ["S", "#"])
        #expect(groups.last?.applications.map(\.name) == ["1Password"])
    }

    @Test("An application found in two directories appears once")
    func duplicatesCollapse() {
        // The search paths overlap, and an app can be both installed and
        // symlinked, so the same bundle identifier arrives twice.
        let system = ApplicationInfo(
            bundleIdentifier: "com.apple.Safari", name: "Safari",
            path: "/System/Applications/Safari.app")
        let user = ApplicationInfo(
            bundleIdentifier: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app")

        let groups = ApplicationCatalog.groups(from: [user, system])

        #expect(groups.count == 1)
        #expect(groups.first?.applications.count == 1)
        // The first one found wins, so search-path order decides.
        #expect(groups.first?.applications.first?.path == "/Applications/Safari.app")
    }

    @Test("Two applications sharing a name keep a stable order")
    func identicalNamesAreOrderedStably() {
        // Sorting by name alone leaves ties to the sort's discretion, and a
        // menu that reshuffles between openings is one nobody can learn.
        let first = app("Preview", id: "com.a.preview")
        let second = app("Preview", id: "com.b.preview")

        let groups = ApplicationCatalog.groups(from: [second, first])

        #expect(groups.first?.applications.map(\.bundleIdentifier) == ["com.a.preview", "com.b.preview"])
    }

    @Test("A Mac with no applications found yields no groups")
    func emptyCatalogYieldsNoGroups() {
        #expect(ApplicationCatalog.groups(from: []).isEmpty)
    }

    @Test("An application with an empty name is filed under #")
    func emptyNameIsFiledUnderSymbol() {
        let nameless = ApplicationInfo(
            bundleIdentifier: "com.example.nameless", name: "", path: "/Applications/x.app")

        #expect(ApplicationCatalog.groups(from: [nameless]).map(\.title) == ["#"])
    }
}

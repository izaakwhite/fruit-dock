/// A run of applications sharing an initial, for a browser menu.
public struct ApplicationGroup: Equatable, Sendable, Identifiable {
    public var id: String { title }

    /// The initial the group is filed under; `#` for anything not a letter.
    public let title: String
    public let applications: [ApplicationInfo]

    public init(title: String, applications: [ApplicationInfo]) {
        self.title = title
        self.applications = applications
    }
}

/// Arranges every installed application into something browsable.
///
/// A flat list of the two hundred-odd bundles on a typical Mac is not a menu
/// anyone can use, so it is filed by initial. Grouping is a decision about
/// presentation, which makes it a pure function here rather than a loop in the
/// menu-building code.
public enum ApplicationCatalog {

    /// Where non-letters are filed, matching how Finder and the App Store
    /// handle names beginning with a digit or a symbol.
    public static let symbolGroupTitle = "#"

    /// - Parameter applications: unsorted, possibly containing the same app
    ///   twice — the standard directories overlap, and an app can be both in
    ///   `/Applications` and symlinked from elsewhere.
    public static func groups(from applications: [ApplicationInfo]) -> [ApplicationGroup] {
        var seen = Set<String>()
        let unique = applications.filter { seen.insert($0.bundleIdentifier).inserted }

        // Sorted by name as shown, not by identifier: the user is looking for
        // "Visual Studio Code", not "com.microsoft.VSCode". The identifier
        // breaks ties only so the order cannot wobble between openings.
        let sorted = unique.sorted {
            let left = $0.name.lowercased(), right = $1.name.lowercased()
            return left == right ? $0.bundleIdentifier < $1.bundleIdentifier : left < right
        }

        var groups: [String: [ApplicationInfo]] = [:]
        for application in sorted {
            groups[title(for: application), default: []].append(application)
        }

        return groups.keys.sorted(by: precedes).map {
            ApplicationGroup(title: $0, applications: groups[$0] ?? [])
        }
    }

    private static func title(for application: ApplicationInfo) -> String {
        guard let initial = application.name.first, initial.isLetter else {
            return symbolGroupTitle
        }
        return initial.uppercased()
    }

    /// Letters in order, with the symbol group after them — a user scanning
    /// for an app by name reads the alphabet first.
    private static func precedes(_ left: String, _ right: String) -> Bool {
        if left == symbolGroupTitle { return false }
        if right == symbolGroupTitle { return true }
        return left < right
    }
}

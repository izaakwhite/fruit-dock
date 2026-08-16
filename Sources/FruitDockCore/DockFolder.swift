/// A folder pinned to the dock — Downloads, and anything else the user added.
///
/// Apple's Dock keeps these in `persistent-others` rather than
/// `persistent-apps`, as `directory-tile` entries with no bundle identifier.
/// They need their own type because almost nothing about an application
/// applies: there is no process, nothing to quit, and no running state.
public struct DockFolder: Equatable, Sendable, Codable, Identifiable {
    public var name: String
    public var path: String
    public var displayAs: DisplayStyle
    public var showAs: ViewStyle

    public var id: String { path }

    public init(
        name: String,
        path: String,
        displayAs: DisplayStyle = .stack,
        showAs: ViewStyle = .automatic
    ) {
        self.name = name
        self.path = path
        self.displayAs = displayAs
        self.showAs = showAs
    }

    /// Whether the tile shows the folder itself or its topmost item.
    ///
    /// Raw values are Apple's, from `displayas`.
    public enum DisplayStyle: Int, Sendable, Codable {
        /// The tile is drawn as the item on top of the pile.
        case stack = 0
        /// The tile is drawn as the folder.
        case folder = 1

        public static func from(_ raw: Int?) -> DisplayStyle {
            raw.flatMap(DisplayStyle.init(rawValue:)) ?? .stack
        }
    }

    /// How the contents are presented when opened. Raw values from `showas`.
    public enum ViewStyle: Int, Sendable, Codable {
        case automatic = 0
        case fan = 1
        case grid = 2
        case list = 3

        public static func from(_ raw: Int?) -> ViewStyle {
            raw.flatMap(ViewStyle.init(rawValue:)) ?? .automatic
        }
    }
}

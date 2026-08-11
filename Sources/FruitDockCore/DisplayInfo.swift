/// A snapshot of one connected display.
///
/// A value type on purpose: tests construct these directly, so no physical
/// monitor is needed to exercise connect and disconnect behaviour.
public struct DisplayInfo: Hashable, Sendable, Identifiable {
    public let id: DisplayID

    /// Human-readable name, for the settings UI. Not an identifier —
    /// two identical monitors can share a name.
    public let name: String

    /// Whether this display currently hosts the system menu bar.
    public let isPrimary: Bool

    /// Whether Apple's own Dock is currently on this display.
    ///
    /// Dynamic, not a fixed property: macOS moves the Dock to whichever
    /// display the user pushes the cursor to the bottom edge of, so this can
    /// change without any display being connected or disconnected.
    public let hostsSystemDock: Bool

    public init(
        id: DisplayID,
        name: String,
        isPrimary: Bool = false,
        hostsSystemDock: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isPrimary = isPrimary
        self.hostsSystemDock = hostsSystemDock
    }
}

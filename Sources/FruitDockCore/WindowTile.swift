/// A minimised window, as the dock needs to draw it.
///
/// Apple's Dock keeps these to the right of the last separator, alongside
/// folders, because they are not applications: there is nothing to launch and
/// nothing to quit, only a window to bring back.
public struct WindowTile: Equatable, Sendable, Identifiable {
    /// The window's own title, shown on hover.
    public var title: String

    /// The application that owns it, so the tile can be badged with its icon
    /// and the right process can be asked to restore it.
    public var application: ApplicationInfo

    /// The owning process. Not `Equatable`-significant on its own — two windows
    /// of one app share it — which is why `id` combines it with the index.
    public var processIdentifier: Int32

    /// Position in that application's window list, which is how the window is
    /// found again when the tile is clicked.
    public var windowIndex: Int

    public var id: String {
        "\(processIdentifier):\(windowIndex)"
    }

    public init(
        title: String,
        application: ApplicationInfo,
        processIdentifier: Int32,
        windowIndex: Int
    ) {
        self.title = title
        self.application = application
        self.processIdentifier = processIdentifier
        self.windowIndex = windowIndex
    }

    /// What the hover label shows.
    ///
    /// An untitled window is common — a blank document, a palette — and
    /// "Untitled" beside the application's name is more use than an empty
    /// label that looks like a rendering fault.
    public var label: String {
        title.isEmpty ? "\(application.name) — Untitled" : title
    }
}

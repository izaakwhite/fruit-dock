import AppKit
import FruitDockCore

/// One dock window, pinned to one display.
///
/// Non-activating on purpose: clicking the dock must not steal focus from the
/// app the user is working in, which a normal window would.
@MainActor
final class DockPanel: NSPanel {
    let displayID: DisplayID
    private let edge: DockEdge
    private let bar: DockBarView

    /// Gap between the dock and the screen edge it sits against.
    private static let margin: CGFloat = 8

    init(display: DisplayInfo, screen: NSScreen, configuration: DockConfiguration) {
        self.displayID = display.id
        self.edge = configuration.edge
        self.bar = DockBarView(isVertical: configuration.edge.isVertical)

        super.init(
            contentRect: .zero,
            // `.nonactivatingPanel` is what keeps focus with the user's app.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Stay put across Spaces rather than following the user around.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        contentView = makeContentView()
        orderFrontRegardless()
    }

    private func makeContentView() -> NSView {
        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 16
        material.layer?.masksToBounds = true

        bar.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            bar.topAnchor.constraint(equalTo: material.topAnchor),
            bar.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        return material
    }

    // MARK: - Contents

    func update(entries: [DockEntry], handlers: DockPanelHandlers) {
        bar.onActivate = handlers.activate
        bar.onQuit = handlers.quit
        bar.onTogglePin = handlers.togglePin
        bar.isPinned = handlers.isPinned

        bar.update(entries: entries)
        resizeAndReposition(itemCount: entries.count)
    }

    func updatePosition() {
        resizeAndReposition(itemCount: nil)
    }

    // MARK: - Geometry

    /// Sizes the panel to its contents, then pins it to the configured edge.
    ///
    /// Size and position are computed together on purpose: the panel's
    /// position depends on how large it is, so resizing without repositioning
    /// leaves it misaligned against its edge.
    private func resizeAndReposition(itemCount: Int?) {
        guard let screen = SystemDisplayProvider.screen(for: displayID) else { return }

        let size = itemCount.map {
            DockBarView.size(forItemCount: $0, isVertical: edge.isVertical)
        } ?? frame.size

        setFrame(Self.frame(for: size, edge: edge, on: screen), display: true)
    }

    /// Places a panel of `size` against `edge` of `screen`.
    ///
    /// `visibleFrame` rather than `frame`, so the dock clears the menu bar and
    /// the system Dock instead of hiding underneath them.
    ///
    /// Coordinates are global and origin is bottom-left, so `minY` is the
    /// bottom edge and `maxY` the top. Each screen has its own offset within
    /// that global space, which is why every edge is expressed relative to
    /// `area` and never to zero.
    static func frame(for size: NSSize, edge: DockEdge, on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame

        switch edge {
        case .bottom:
            return NSRect(
                x: area.midX - size.width / 2,
                y: area.minY + margin,
                width: size.width,
                height: size.height
            )
        case .top:
            return NSRect(
                x: area.midX - size.width / 2,
                y: area.maxY - size.height - margin,
                width: size.width,
                height: size.height
            )
        case .left:
            return NSRect(
                x: area.minX + margin,
                y: area.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .right:
            return NSRect(
                x: area.maxX - size.width - margin,
                y: area.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }
}

/// Callbacks a panel invokes on user action.
///
/// Grouped into one value so the panel takes a single collaborator rather
/// than four loose closures.
@MainActor
struct DockPanelHandlers {
    let activate: (ApplicationInfo) -> Void
    let quit: (ApplicationInfo) -> Void
    let togglePin: (ApplicationInfo) -> Void
    let isPinned: (ApplicationInfo) -> Bool
}

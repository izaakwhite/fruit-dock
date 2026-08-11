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
    private let iconSize: Double

    init(display: DisplayInfo, screen: NSScreen, configuration: DockConfiguration) {
        self.displayID = display.id
        self.edge = configuration.edge
        self.iconSize = configuration.iconSize

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

        contentView = DockContentView(label: display.name, iconSize: iconSize)

        reposition(on: screen)
        orderFrontRegardless()
    }

    /// Places the panel against the configured edge of its display.
    ///
    /// `visibleFrame` is used rather than `frame` so the panel sits clear of
    /// the menu bar and the system Dock instead of underneath them.
    func reposition(on screen: NSScreen) {
        let area = screen.visibleFrame
        let thickness = iconSize + 16
        let length = min(area.width * 0.5, 420)

        let rect: NSRect
        switch edge {
        case .bottom:
            rect = NSRect(x: area.midX - length / 2, y: area.minY + 8, width: length, height: thickness)
        case .top:
            rect = NSRect(x: area.midX - length / 2, y: area.maxY - thickness - 8, width: length, height: thickness)
        case .left:
            rect = NSRect(x: area.minX + 8, y: area.midY - length / 2, width: thickness, height: length)
        case .right:
            rect = NSRect(x: area.maxX - thickness - 8, y: area.midY - length / 2, width: thickness, height: length)
        }

        setFrame(rect, display: true)
    }

    /// Re-resolves the screen before repositioning, for resolution changes.
    func updatePosition() {
        guard let screen = SystemDisplayProvider.screen(for: displayID) else { return }
        reposition(on: screen)
    }
}

/// Placeholder contents.
///
/// Phase 1 only needs to prove a non-activating panel lands on the correct
/// display; showing the display's name makes that verifiable at a glance.
/// Real icons arrive in Phase 3.
@MainActor
private final class DockContentView: NSView {
    private let label: String
    private let iconSize: Double

    init(label: String, iconSize: Double) {
        self.label = label
        self.iconSize = iconSize
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard subviews.isEmpty else { return }

        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 16
        material.layer?.masksToBounds = true
        material.translatesAutoresizingMaskIntoConstraints = false
        addSubview(material)

        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 12, weight: .medium)
        text.textColor = .secondaryLabelColor
        text.alignment = .center
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)

        NSLayoutConstraint.activate([
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.topAnchor.constraint(equalTo: topAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor),

            text.centerXAnchor.constraint(equalTo: centerXAnchor),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
        ])
    }
}

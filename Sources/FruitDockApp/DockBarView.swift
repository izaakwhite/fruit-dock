import AppKit
import FruitDockCore

/// Renders the dock's icons and reports clicks.
///
/// Holds no decisions: it is handed a finished list of entries and draws it.
/// What belongs in the list is `DockContentBuilder`'s job.
@MainActor
final class DockBarView: NSView {
    /// Point size of one icon, excluding padding.
    static let iconSize: CGFloat = 48
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 10
    /// Vertical room reserved beneath an icon for the running dot.
    static let indicatorLane: CGFloat = 8

    var onActivate: ((ApplicationInfo) -> Void)?
    var onQuit: ((ApplicationInfo) -> Void)?
    var onTogglePin: ((ApplicationInfo) -> Void)?
    var isPinned: ((ApplicationInfo) -> Bool)?

    private var entries: [DockEntry] = []
    private let stack = NSStackView()
    private let isVertical: Bool

    init(isVertical: Bool) {
        self.isVertical = isVertical
        super.init(frame: .zero)

        stack.orientation = isVertical ? .vertical : .horizontal
        stack.spacing = Self.spacing
        stack.alignment = isVertical ? .centerX : .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The size this bar needs for `count` icons, in the current orientation.
    static func size(forItemCount count: Int, isVertical: Bool) -> NSSize {
        let visible = max(count, 1)
        let run = padding * 2
            + CGFloat(visible) * iconSize
            + CGFloat(max(visible - 1, 0)) * spacing
        let breadth = padding * 2 + iconSize + indicatorLane

        return isVertical
            ? NSSize(width: breadth, height: run)
            : NSSize(width: run, height: breadth)
    }

    func update(entries: [DockEntry]) {
        guard entries != self.entries else { return }
        self.entries = entries

        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for entry in entries {
            stack.addArrangedSubview(makeIconView(for: entry))
        }
    }

    private func makeIconView(for entry: DockEntry) -> NSView {
        let container = IconView(entry: entry)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.onActivate = { [weak self] in self?.onActivate?(entry.application) }
        container.onQuit = { [weak self] in self?.onQuit?(entry.application) }
        container.onTogglePin = { [weak self] in self?.onTogglePin?(entry.application) }
        container.isCurrentlyPinned = isPinned?(entry.application) ?? entry.isPinned

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.iconSize),
            container.heightAnchor.constraint(equalToConstant: Self.iconSize + Self.indicatorLane),
        ])
        return container
    }
}

/// A single dock icon, its running indicator, and its context menu.
@MainActor
private final class IconView: NSView {
    private let entry: DockEntry

    var onActivate: (() -> Void)?
    var onQuit: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var isCurrentlyPinned = false

    private let imageView = NSImageView()
    private var isHovered = false { didSet { needsDisplay = true } }

    init(entry: DockEntry) {
        self.entry = entry
        super.init(frame: .zero)
        wantsLayer = true

        imageView.image = NSWorkspace.shared.icon(forFile: entry.application.path)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: widthAnchor),
        ])

        toolTip = entry.application.name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseUp(with event: NSEvent) {
        onActivate?()
    }

    /// Right-click context menu. FR-3.5.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        if entry.isRunning {
            let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
            quit.target = self
            menu.addItem(quit)
        }

        let pin = NSMenuItem(
            title: isCurrentlyPinned ? "Remove from Dock" : "Keep in Dock",
            action: #selector(togglePin),
            keyEquivalent: ""
        )
        pin.target = self
        menu.addItem(pin)

        return menu
    }

    @objc private func quitApp() { onQuit?() }
    @objc private func togglePin() { onTogglePin?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHovered {
            let iconArea = NSRect(x: 0, y: bounds.height - bounds.width, width: bounds.width, height: bounds.width)
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: iconArea.insetBy(dx: -2, dy: -2), xRadius: 8, yRadius: 8).fill()
        }

        // Running indicator: a dot in the reserved lane beneath the icon.
        guard entry.isRunning else { return }
        let diameter: CGFloat = 4
        let dot = NSRect(
            x: bounds.midX - diameter / 2,
            y: 1,
            width: diameter,
            height: diameter
        )
        NSColor.labelColor.withAlphaComponent(0.75).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }
}

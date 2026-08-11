import AppKit
import FruitDockCore

/// Actions a dock element can trigger.
@MainActor
struct DockBarHandlers {
    let activate: (ApplicationInfo) -> Void
    let quit: (ApplicationInfo) -> Void
    let togglePin: (ApplicationInfo) -> Void
    let isPinned: (ApplicationInfo) -> Bool
    let openTrash: () -> Void
}

/// Renders the dock's elements and reports clicks.
///
/// Holds no decisions: it is handed a finished list of elements and draws it.
/// What belongs in the list is `DockContentBuilder`'s job.
@MainActor
final class DockBarView: NSView {
    static let iconSize: CGFloat = 48
    static let spacing: CGFloat = 6
    static let padding: CGFloat = 8
    /// Room beneath an icon for the running dot.
    static let indicatorLane: CGFloat = 7
    /// A separator takes far less room than an icon.
    static let separatorExtent: CGFloat = 11

    var handlers: DockBarHandlers?

    private var elements: [DockElement] = []
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

    /// Extent one element occupies along the dock's long axis.
    private static func extent(of element: DockElement) -> CGFloat {
        switch element {
        case .separator: separatorExtent
        case .app, .trash: iconSize
        }
    }

    /// The size this bar needs for `elements`, in the current orientation.
    static func size(for elements: [DockElement], isVertical: Bool) -> NSSize {
        guard !elements.isEmpty else {
            return NSSize(width: iconSize, height: iconSize)
        }

        let run = padding * 2
            + elements.reduce(0) { $0 + extent(of: $1) }
            + CGFloat(elements.count - 1) * spacing
        let breadth = padding * 2 + iconSize + indicatorLane

        return isVertical
            ? NSSize(width: breadth, height: run)
            : NSSize(width: run, height: breadth)
    }

    func update(elements: [DockElement]) {
        guard elements != self.elements else { return }
        self.elements = elements

        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for element in elements {
            stack.addArrangedSubview(makeView(for: element))
        }
    }

    private func makeView(for element: DockElement) -> NSView {
        let view: NSView
        let extent = Self.extent(of: element)

        switch element {
        case .separator:
            view = SeparatorView(isVertical: isVertical)

        case .trash:
            let trash = IconView(
                icon: NSWorkspace.shared.icon(forFile: Self.trashPath),
                label: "Trash",
                isRunning: false
            )
            trash.onActivate = { [weak self] in self?.handlers?.openTrash() }
            view = trash

        case .app(let entry):
            let application = entry.application
            let icon = IconView(
                icon: NSWorkspace.shared.icon(forFile: application.path),
                label: application.name,
                isRunning: entry.isRunning
            )
            icon.onActivate = { [weak self] in self?.handlers?.activate(application) }
            icon.onQuit = entry.isRunning
                ? { [weak self] in self?.handlers?.quit(application) }
                : nil
            icon.onTogglePin = { [weak self] in self?.handlers?.togglePin(application) }
            icon.isCurrentlyPinned = handlers?.isPinned(application) ?? entry.isPinned
            view = icon
        }

        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: isVertical ? Self.iconSize : extent),
            view.heightAnchor.constraint(
                equalToConstant: isVertical ? extent : Self.iconSize + Self.indicatorLane
            ),
        ])
        return view
    }

    private static var trashPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".Trash")
    }
}

/// The hairline dividing applications from Trash, as in Apple's Dock.
@MainActor
private final class SeparatorView: NSView {
    private let isVertical: Bool

    init(isVertical: Bool) {
        self.isVertical = isVertical
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = SystemAppearance.increasesContrast ? 0.5 : 0.22
        NSColor.labelColor.withAlphaComponent(alpha).setFill()

        let line: NSRect = isVertical
            ? NSRect(x: bounds.width * 0.2, y: bounds.midY, width: bounds.width * 0.6, height: 1)
            : NSRect(x: bounds.midX, y: bounds.height * 0.2, width: 1, height: bounds.height * 0.6)
        line.fill()
    }
}

/// A single dock icon, its running indicator, and its context menu.
@MainActor
private final class IconView: NSView {
    private let label: String
    private let isRunning: Bool

    var onActivate: (() -> Void)?
    var onQuit: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var isCurrentlyPinned = false

    private let imageView = NSImageView()
    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
            applyHoverScale()
        }
    }

    init(icon: NSImage, label: String, isRunning: Bool) {
        self.label = label
        self.isRunning = isRunning
        super.init(frame: .zero)
        wantsLayer = true

        imageView.image = icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        // Scale about the icon's centre so magnification grows evenly.
        imageView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: widthAnchor),
        ])

        toolTip = label
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
    override func mouseUp(with event: NSEvent) { onActivate?() }

    /// Grows the icon slightly under the cursor.
    ///
    /// Skipped entirely under Reduce Motion, where the scale is applied
    /// without animation rather than not at all — the affordance survives,
    /// the movement does not.
    private func applyHoverScale() {
        let scale: CGFloat = isHovered ? 1.12 : 1
        let transform = CATransform3DMakeScale(scale, scale, 1)

        guard !SystemAppearance.reducesMotion else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageView.layer?.transform = transform
            CATransaction.commit()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            imageView.animator().layer?.transform = transform
        }
    }

    /// Right-click context menu. FR-3.5.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        if onQuit != nil {
            let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
            quit.target = self
            menu.addItem(quit)
        }

        if onTogglePin != nil {
            let pin = NSMenuItem(
                title: isCurrentlyPinned ? "Remove from Dock" : "Keep in Dock",
                action: #selector(togglePin),
                keyEquivalent: ""
            )
            pin.target = self
            menu.addItem(pin)
        }

        return menu.items.isEmpty ? nil : menu
    }

    @objc private func quitApp() { onQuit?() }
    @objc private func togglePin() { onTogglePin?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHovered {
            let iconArea = NSRect(
                x: 0, y: bounds.height - bounds.width,
                width: bounds.width, height: bounds.width
            )
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: iconArea.insetBy(dx: -1, dy: -1), xRadius: 9, yRadius: 9).fill()
        }

        guard isRunning else { return }
        let diameter: CGFloat = 4.5
        let dot = NSRect(
            x: bounds.midX - diameter / 2,
            y: 1,
            width: diameter,
            height: diameter
        )
        // Full-strength label colour, so the indicator reads without relying
        // on hue — Differentiate Without Color safe.
        NSColor.labelColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }
}

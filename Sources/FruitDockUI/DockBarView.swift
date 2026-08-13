import AppKit
import FruitDockCore

/// Renders the dock's elements and reports interaction.
///
/// Holds no decisions: it is handed a finished list of elements and draws it.
/// What belongs in the list is `DockContentBuilder`'s job; what a click means
/// is the coordinator's.
@MainActor
final class DockBarView: NSView {
    /// Fallback only. The size actually drawn is `iconSize`, which comes from
    /// the configuration scaled to the display — see `DockSizing`.
    static let defaultIconSize: CGFloat = 48
    static let spacing: CGFloat = 6
    static let padding: CGFloat = 8
    /// Room beneath an icon for the running dot.
    static let indicatorLane: CGFloat = 7
    /// A separator takes far less room than an icon.
    static let separatorExtent: CGFloat = 11

    weak var actionHandler: (any DockActionHandling)?

    /// The display this bar is drawn on, so a click can open the app here
    /// rather than wherever macOS would otherwise put it.
    var displayID: DisplayID?

    /// Reports the hovered element's name and its bounds in this view's
    /// window, or nil when nothing is hovered.
    var onHover: ((String, NSRect)?) -> Void = { _ in }

    private var elements: [DockElement] = []
    private let stack = NSStackView()
    private let isVertical: Bool

    /// Scaled to this bar's display rather than fixed, so a laptop and a large
    /// external monitor each get a dock proportionate to what they are.
    let iconSize: CGFloat

    init(isVertical: Bool, iconSize: CGFloat = defaultIconSize) {
        self.isVertical = isVertical
        self.iconSize = iconSize
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
    private static func extent(of element: DockElement, iconSize: CGFloat) -> CGFloat {
        switch element {
        case .separator: separatorExtent
        case .app, .trash: iconSize
        }
    }

    /// The size a bar needs for `elements`, in the given orientation.
    ///
    /// Static and fully parameterised so the panel can ask what size it will
    /// need before there is a bar to ask — and so it can be tested without one.
    static func size(
        for elements: [DockElement],
        isVertical: Bool,
        iconSize: CGFloat = defaultIconSize
    ) -> NSSize {
        guard !elements.isEmpty else {
            return NSSize(width: iconSize, height: iconSize)
        }

        let run = padding * 2
            + elements.reduce(0) { $0 + extent(of: $1, iconSize: iconSize) }
            + CGFloat(elements.count - 1) * spacing
        let breadth = padding * 2 + iconSize + indicatorLane

        return isVertical
            ? NSSize(width: breadth, height: run)
            : NSSize(width: run, height: breadth)
    }

    func update(elements: [DockElement]) {
        guard elements != self.elements else { return }
        self.elements = elements

        // Any hovered icon is about to be destroyed; its label must go too.
        onHover(nil)

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
        let extent = Self.extent(of: element, iconSize: iconSize)

        switch element {
        case .separator:
            view = SeparatorView(isVertical: isVertical)

        case .trash:
            let isFull = Self.trashHasContents
            let label = isFull ? "Trash — Full" : "Trash"
            let trash = IconView(
                icon: trashIcon(isFull: isFull),
                label: label,
                isRunning: false
            )
            trash.onActivate = { [weak self] in self?.actionHandler?.openTrash() }
            attachHoverReporting(to: trash, label: label)
            view = trash

        case .app(let entry):
            let application = entry.application
            let icon = IconView(
                icon: NSWorkspace.shared.icon(forFile: application.path),
                label: application.name,
                isRunning: entry.isRunning
            )
            icon.onActivate = { [weak self] in
                self?.actionHandler?.activate(application, on: self?.displayID)
            }
            icon.onQuit = entry.isRunning
                ? { [weak self] in self?.actionHandler?.quit(application) }
                : nil
            icon.onTogglePin = { [weak self] in self?.actionHandler?.togglePin(application) }
            icon.isCurrentlyPinned = actionHandler?.isPinned(application) ?? entry.isPinned
            attachHoverReporting(to: icon, label: application.name)
            view = icon
        }

        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: isVertical ? iconSize : extent),
            view.heightAnchor.constraint(
                equalToConstant: isVertical ? extent : iconSize + Self.indicatorLane
            ),
        ])
        return view
    }

    private func attachHoverReporting(to icon: IconView, label: String) {
        icon.onHoverChange = { [weak self, weak icon] isHovered in
            guard let self, let icon else { return }
            guard isHovered else {
                self.onHover(nil)
                return
            }
            // Reported in window coordinates; the panel converts to screen,
            // since only it knows which window it belongs to.
            self.onHover((label, icon.convert(icon.bounds, to: nil)))
        }
    }

    private static var trashPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".Trash")
    }

    /// Whether anything is in the Trash, which decides which icon to draw.
    ///
    /// Hidden files are included: `.DS_Store` aside, an item the Finder shows
    /// as present should not read as empty here.
    private static var trashHasContents: Bool {
        let contents = try? FileManager.default.contentsOfDirectory(atPath: trashPath)
        return contents?.contains { $0 != ".DS_Store" } ?? false
    }

    /// The Dock's own Trash artwork, matching state and appearance.
    ///
    /// Loaded from `Dock.app`'s resources because that is literally the image
    /// the real Dock draws, and the point here is to be indistinguishable from
    /// it. `icon(forFile:)` on `~/.Trash` answers with the icon for a *folder
    /// at that path* — a plain folder, not a bin, and unchanged as the Trash
    /// fills. `NSImage.trashEmptyName` is closer but is the generic system
    /// symbol rather than the Dock's.
    ///
    /// The `2` suffix is the dark-appearance variant: the unsuffixed art is a
    /// light bin meant for a light dock, and drawing it in dark mode gives a
    /// near-white bin against everything around it.
    ///
    /// Undocumented paths, so every step degrades: a missing file falls back to
    /// the system symbol, and a missing symbol to the folder icon. A renamed
    /// resource costs fidelity, never a crash or a blank tile.
    private func trashIcon(isFull: Bool) -> NSImage {
        let isDark = effectiveAppearance.bestMatch(
            from: [.aqua, .darkAqua]) == .darkAqua

        let name = "s-trash\(isFull ? "full" : "empty")\(isDark ? "2" : "")"
        let path = "\(Self.dockResources)/\(name)@2x.png"

        if let art = NSImage(contentsOfFile: path) {
            // Tagged as a template so AppKit will not re-tint artwork that is
            // already the right colour for this appearance.
            art.isTemplate = false
            return art
        }

        let symbol = isFull ? NSImage.trashFullName : NSImage.trashEmptyName
        return NSImage(named: symbol) ?? NSWorkspace.shared.icon(forFile: Self.trashPath)
    }

    private static let dockResources =
        "/System/Library/CoreServices/Dock.app/Contents/Resources"
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
    private let isRunning: Bool

    var onActivate: (() -> Void)?
    var onQuit: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var isCurrentlyPinned = false

    private let imageView = NSImageView()
    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
            applyHoverScale()
            onHoverChange?(isHovered)
        }
    }

    init(icon: NSImage, label: String, isRunning: Bool) {
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

    /// Accept clicks even though the app is never frontmost.
    ///
    /// fruit-dock is an accessory app in a non-activating panel, so it never
    /// becomes active — which makes *every* click a first-mouse click. Without
    /// this, AppKit spends each one activating the window and the dock appears
    /// to ignore being clicked entirely.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Claims the click so the matching `mouseUp` is routed back here.
    ///
    /// A view that leaves `mouseDown` to `super` does not own the drag
    /// session, and its `mouseUp` never arrives.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        // Only count a release that lands on the icon it started on.
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }

        // The icon is about to be replaced or the app about to come forward;
        // either way the label should not linger.
        isHovered = false
        onActivate?()
    }

    /// Grows the icon slightly under the cursor.
    ///
    /// Under Reduce Motion the scale is applied without animation rather than
    /// skipped — the affordance survives, the movement does not.
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
            x: bounds.midX - diameter / 2, y: 1, width: diameter, height: diameter)
        // Full-strength label colour, so the indicator reads without relying
        // on hue — Differentiate Without Color safe.
        NSColor.labelColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }
}

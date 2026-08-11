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
    private var background: NSView?

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

        // Start invisible; `fadeIn()` reveals once contents and size are set,
        // so the panel never flashes at the wrong size or on the wrong screen.
        alphaValue = 0
        orderFrontRegardless()
    }

    // MARK: - Appearance

    private func makeContentView() -> NSView {
        let container = makeBackgroundView()
        background = container

        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// Blurred material normally; a solid fill under Reduce Transparency.
    ///
    /// Rendering the blur regardless would produce exactly the effect the user
    /// asked the system not to produce.
    private func makeBackgroundView() -> NSView {
        let radius: CGFloat = 18

        if SystemAppearance.reducesTransparency {
            let solid = NSView()
            solid.wantsLayer = true
            solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            solid.layer?.cornerRadius = radius
            solid.layer?.masksToBounds = true
            solid.layer?.borderWidth = 1
            solid.layer?.borderColor = NSColor.separatorColor.cgColor
            return solid
        }

        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = radius
        material.layer?.masksToBounds = true

        if SystemAppearance.increasesContrast {
            material.layer?.borderWidth = 1
            material.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        return material
    }

    /// Rebuilds the background after an accessibility setting changes.
    func refreshAppearance() {
        contentView = makeContentView()
    }

    // MARK: - Transitions

    func fadeIn() {
        let duration = SystemAppearance.transitionDuration
        guard duration > 0 else {
            alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    /// Fades out, then closes.
    ///
    /// The panel must not be closed until the animation finishes, or it
    /// vanishes instantly and the fade is never seen.
    func fadeOutAndClose() {
        let duration = SystemAppearance.transitionDuration
        guard duration > 0 else {
            close()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.close()
        }
    }

    // MARK: - Contents

    func update(elements: [DockElement], handlers: DockBarHandlers) {
        bar.handlers = handlers
        bar.update(elements: elements)
        resizeAndReposition(elements: elements)
    }

    func updatePosition() {
        resizeAndReposition(elements: nil)
    }

    // MARK: - Geometry

    /// Sizes the panel to its contents, then pins it to the configured edge.
    ///
    /// Size and position are computed together on purpose: the position
    /// depends on the size, so resizing without repositioning leaves the panel
    /// misaligned against its edge.
    private func resizeAndReposition(elements: [DockElement]?) {
        guard let screen = SystemDisplayProvider.screen(for: displayID) else { return }

        let size = elements.map {
            DockBarView.size(for: $0, isVertical: edge.isVertical)
        } ?? frame.size

        let target = Self.frame(for: size, edge: edge, on: screen)

        // Only animate a move once the panel is actually visible; animating
        // from the zero rect at construction produces a slide from the corner.
        let shouldAnimate = alphaValue > 0
            && !frame.equalTo(.zero)
            && SystemAppearance.transitionDuration > 0

        guard shouldAnimate else {
            setFrame(target, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = SystemAppearance.transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(target, display: true)
        }
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
                x: area.midX - size.width / 2, y: area.minY + margin,
                width: size.width, height: size.height)
        case .top:
            return NSRect(
                x: area.midX - size.width / 2, y: area.maxY - size.height - margin,
                width: size.width, height: size.height)
        case .left:
            return NSRect(
                x: area.minX + margin, y: area.midY - size.height / 2,
                width: size.width, height: size.height)
        case .right:
            return NSRect(
                x: area.maxX - size.width - margin, y: area.midY - size.height / 2,
                width: size.width, height: size.height)
        }
    }
}

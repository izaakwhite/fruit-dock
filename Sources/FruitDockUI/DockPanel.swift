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
    private let hoverLabel = HoverLabelPanel()

    /// Forwarded to the bar so clicks reach the coordinator.
    weak var actionHandler: (any DockActionHandling)? {
        didSet { bar.actionHandler = actionHandler }
    }

    /// Gap between the dock and the screen edge it sits against.
    private static let margin: CGFloat = 8

    init(display: DisplayInfo, screen: NSScreen, configuration: DockConfiguration) {
        self.displayID = display.id
        self.edge = configuration.edge
        self.bar = DockBarView(isVertical: configuration.edge.isVertical)
        bar.displayID = display.id

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

        // The bar reports hover in window coordinates; only the panel knows
        // which window and screen those belong to.
        bar.onHover = { [weak self] hovered in
            guard let self else { return }
            guard let (name, rectInWindow) = hovered, let screen = self.screen else {
                self.hoverLabel.hide()
                return
            }
            self.hoverLabel.show(
                text: name,
                near: self.convertToScreen(rectInWindow),
                edge: self.edge,
                on: screen
            )
        }

        // Start invisible; `fadeIn()` reveals once contents and size are set,
        // so the panel never flashes at the wrong size or on the wrong screen.
        alphaValue = 0
        orderFrontRegardless()
    }

    override func close() {
        // The label is a separate window and would outlive its dock otherwise.
        hoverLabel.orderOut(nil)
        super.close()
    }

    // MARK: - Appearance

    private func makeContentView() -> NSView {
        let container = makeBackgroundView()
        background = container
        return container
    }

    /// Liquid Glass on macOS 26+, the pre-Glass blurred material below that,
    /// and a solid fill under Reduce Transparency regardless of OS version.
    ///
    /// Rendering translucency at all under Reduce Transparency would produce
    /// exactly the effect the user asked the system not to produce, so that
    /// check comes first and short-circuits both material paths — see
    /// backlog T8 Tier 1 and issue #4.
    private func makeBackgroundView() -> NSView {
        let radius: CGFloat = 18

        if SystemAppearance.reducesTransparency {
            return Self.solidBackground(radius: radius, embedding: bar)
        }
        if #available(macOS 26, *) {
            return Self.glassBackground(radius: radius, embedding: bar)
        }
        return Self.visualEffectBackground(radius: radius, embedding: bar)
    }

    private static func solidBackground(radius: CGFloat, embedding content: NSView) -> NSView {
        let solid = NSView()
        solid.wantsLayer = true
        solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        solid.layer?.cornerRadius = radius
        solid.layer?.masksToBounds = true
        solid.layer?.borderWidth = 1
        solid.layer?.borderColor = NSColor.separatorColor.cgColor
        embed(content, edgeToEdgeIn: solid)
        return solid
    }

    private static func visualEffectBackground(radius: CGFloat, embedding content: NSView) -> NSView {
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
        embed(content, edgeToEdgeIn: material)
        return material
    }

    /// `NSGlassEffectView` is new in macOS 26 (Tahoe) — confirmed against
    /// live Apple documentation (see PR description for sources), not
    /// assumed. Content is attached through its documented `contentView`
    /// property, which AppKit ties to the glass's bounds via Auto Layout and
    /// uses to keep the content legible as the glass adapts to what's behind
    /// it — an ordinary `addSubview` would skip that treatment.
    ///
    /// Increase Contrast's border is drawn on a plain wrapping layer instead
    /// of the glass view's own layer: `cornerRadius` is the only shape control
    /// AppKit documents for `NSGlassEffectView`, and poking at `.layer`
    /// directly on a type whose rendering AppKit otherwise manages privately
    /// is exactly the kind of assumption this issue was not supposed to ship
    /// unverified.
    @available(macOS 26, *)
    private static func glassBackground(radius: CGFloat, embedding content: NSView) -> NSView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = radius
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content

        guard SystemAppearance.increasesContrast else { return glass }

        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = radius
        wrapper.layer?.masksToBounds = true
        wrapper.layer?.borderWidth = 1
        wrapper.layer?.borderColor = NSColor.separatorColor.cgColor
        embed(glass, edgeToEdgeIn: wrapper)
        return wrapper
    }

    private static func embed(_ content: NSView, edgeToEdgeIn container: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    /// Rebuilds the background after an accessibility setting changes.
    func refreshAppearance() {
        contentView = makeContentView()
        // The label is a separate window with its own background; it must be
        // rebuilt too, or it keeps rendering translucent after Reduce
        // Transparency is turned on until the next hover recreates it.
        hoverLabel.refreshAppearance()
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
            MainActor.assumeIsolated {
                self?.close()
            }
        }
    }

    // MARK: - Contents

    func update(elements: [DockElement]) {
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
        // The arithmetic itself lives in `DockLayout`, where it is tested
        // against literal coordinates — including displays whose origin is
        // negative or stacked above the primary, which no single-monitor test
        // would ever reach. This is only the conversion.
        NSRect(
            DockLayout.frame(
                for: ScreenSize(size),
                edge: edge,
                // `visibleFrame`, so the dock clears the menu bar and Apple's
                // Dock rather than hiding underneath them.
                in: ScreenRect(screen.visibleFrame),
                margin: margin
            )
        )
    }
}

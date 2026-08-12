import AppKit
import FruitDockCore

/// The floating name that appears beside a hovered icon, as in Apple's Dock.
///
/// A separate window rather than a subview: the name sits *outside* the dock's
/// bounds, and a subview would be clipped by the panel's rounded corners.
@MainActor
final class HoverLabelPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private var background: NSView?

    private static let horizontalPadding: CGFloat = 10
    private static let verticalPadding: CGFloat = 5
    private static let cornerRadius: CGFloat = 6
    /// Distance between the label and the icon it describes.
    private static let gap: CGFloat = 8

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Above the dock itself, or the dock would occlude its own label.
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true  // never steal a click meant for the icon

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center

        contentView = makeContentView()
        alphaValue = 0
    }

    // MARK: - Appearance

    private func makeContentView() -> NSView {
        let container = Self.makeBackground(embedding: label)
        background = container
        return container
    }

    /// Rebuilds the background after an accessibility setting changes.
    ///
    /// This label previously never checked Reduce Transparency at all — see
    /// PR description. Fixing that here, alongside Liquid Glass adoption,
    /// closes that gap rather than propagating it into a third material.
    func refreshAppearance() {
        contentView = makeContentView()
    }

    /// Liquid Glass on macOS 26+, `.toolTip` material below that, and a solid
    /// fill under Reduce Transparency regardless of OS version — matching
    /// `DockPanel.makeBackgroundView()`. See backlog T8 Tier 1.
    private static func makeBackground(embedding label: NSView) -> NSView {
        let radius = cornerRadius

        if SystemAppearance.reducesTransparency {
            return solidBackground(radius: radius, embedding: label)
        }
        if #available(macOS 26, *) {
            return glassBackground(radius: radius, embedding: label)
        }
        return toolTipBackground(radius: radius, embedding: label)
    }

    private static func solidBackground(radius: CGFloat, embedding label: NSView) -> NSView {
        let solid = NSView()
        solid.wantsLayer = true
        solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        solid.layer?.cornerRadius = radius
        solid.layer?.masksToBounds = true
        embedWithPadding(label, in: solid)
        return solid
    }

    private static func toolTipBackground(radius: CGFloat, embedding label: NSView) -> NSView {
        let material = NSVisualEffectView()
        material.material = .toolTip
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = radius
        material.layer?.masksToBounds = true
        embedWithPadding(label, in: material)
        return material
    }

    /// See the equivalent note in `DockPanel.glassBackground` about using
    /// `contentView` rather than `addSubview`. The label needs padding that
    /// `contentView`'s edge-to-edge Auto Layout tie doesn't provide on its
    /// own, so the padding lives in an intermediate plain view that becomes
    /// the glass's `contentView`.
    @available(macOS 26, *)
    private static func glassBackground(radius: CGFloat, embedding label: NSView) -> NSView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = radius
        glass.contentView = paddedWrapper(around: label)
        return glass
    }

    private static func paddedWrapper(around label: NSView) -> NSView {
        let wrapper = NSView()
        embedWithPadding(label, in: wrapper)
        return wrapper
    }

    private static func embedWithPadding(_ label: NSView, in container: NSView) {
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: container.leadingAnchor, constant: horizontalPadding),
            label.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -horizontalPadding),
            label.topAnchor.constraint(
                equalTo: container.topAnchor, constant: verticalPadding),
            label.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -verticalPadding),
        ])
    }

    /// Shows `text` adjacent to `iconFrame`, which must be in screen
    /// coordinates, placed on the side away from the dock's edge.
    func show(text: String, near iconFrame: NSRect, edge: DockEdge, on screen: NSScreen) {
        label.stringValue = text

        let size = NSSize(
            width: label.intrinsicContentSize.width + Self.horizontalPadding * 2,
            height: label.intrinsicContentSize.height + Self.verticalPadding * 2
        )

        var origin: NSPoint
        switch edge {
        case .bottom:
            origin = NSPoint(x: iconFrame.midX - size.width / 2, y: iconFrame.maxY + Self.gap)
        case .top:
            origin = NSPoint(
                x: iconFrame.midX - size.width / 2, y: iconFrame.minY - size.height - Self.gap)
        case .left:
            origin = NSPoint(x: iconFrame.maxX + Self.gap, y: iconFrame.midY - size.height / 2)
        case .right:
            origin = NSPoint(
                x: iconFrame.minX - size.width - Self.gap, y: iconFrame.midY - size.height / 2)
        }

        // Keep the label on screen: a long app name beside the first or last
        // icon would otherwise run off the edge.
        let bounds = screen.visibleFrame
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
        origin.y = min(max(origin.y, bounds.minY + 4), bounds.maxY - size.height - 4)

        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFrontRegardless()

        fade(to: 1)
    }

    func hide() {
        fade(to: 0)
    }

    private func fade(to alpha: CGFloat) {
        let duration = SystemAppearance.transitionDuration
        guard duration > 0 else {
            alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            // Faster than the dock's own transitions; a label that lags the
            // cursor feels broken.
            context.duration = duration * 0.5
            animator().alphaValue = alpha
        }
    }
}

import AppKit
import FruitDockCore

/// The floating name that appears beside a hovered icon, as in Apple's Dock.
///
/// A separate window rather than a subview: the name sits *outside* the dock's
/// bounds, and a subview would be clipped by the panel's rounded corners.
@MainActor
final class HoverLabelPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let background = NSVisualEffectView()

    private static let horizontalPadding: CGFloat = 10
    private static let verticalPadding: CGFloat = 5
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
        label.translatesAutoresizingMaskIntoConstraints = false

        background.material = .toolTip
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        background.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: background.leadingAnchor, constant: Self.horizontalPadding),
            label.trailingAnchor.constraint(
                equalTo: background.trailingAnchor, constant: -Self.horizontalPadding),
            label.topAnchor.constraint(
                equalTo: background.topAnchor, constant: Self.verticalPadding),
            label.bottomAnchor.constraint(
                equalTo: background.bottomAnchor, constant: -Self.verticalPadding),
        ])

        contentView = background
        alphaValue = 0
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

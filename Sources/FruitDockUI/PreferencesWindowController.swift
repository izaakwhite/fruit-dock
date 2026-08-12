import AppKit

/// The Coexist/Replace choice, in one place.
///
/// `DockConfiguration.avoidsSystemDockDisplay` is the underlying storage —
/// unchanged, so existing persisted settings and `DockCoordinatorTests`
/// keep meaning what they already mean. This is a friendlier name for the
/// same bool where the UI needs to talk about it as a choice rather than a
/// checkbox.
enum SystemDockRelationship: Equatable {
    /// Never render on the display Apple's Dock currently occupies. As the
    /// system Dock moves, ours moves out of its way and onto whichever
    /// display it isn't on — `DockCoordinator`'s existing display-change
    /// wiring already does this, unaided; nothing here has to poll or
    /// relocate anything itself.
    case coexist
    /// Render on every display, including the one hosting Apple's Dock.
    case replace

    var avoidsSystemDockDisplay: Bool {
        self == .coexist
    }

    init(avoidsSystemDockDisplay: Bool) {
        self = avoidsSystemDockDisplay ? .coexist : .replace
    }
}

/// A standard, activating settings window — distinct from the dock panels,
/// which are deliberately non-activating so a click never steals focus. A
/// settings window is the one surface in this app where activation is
/// exactly what should happen when it opens.
@MainActor
final class PreferencesWindowController: NSWindowController {
    private let coexistButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let replaceButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)

    /// Reads the live setting when the window opens and writes it back on
    /// selection. A closure pair rather than holding `DockCoordinator`
    /// directly, so this file doesn't need to import `FruitDockCore` just to
    /// read one property — matching how `DockPanel`'s `onHover` and
    /// `PanelPresenter.actionHandler` are wired elsewhere in this codebase.
    var currentRelationship: (() -> SystemDockRelationship)?
    var setRelationship: ((SystemDockRelationship) -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "fruit-dock Settings"
        window.isReleasedWhenClosed = false
        // Preferences windows don't remember a size the user never had a
        // reason to change.
        window.center()

        self.init(window: window)
        window.contentView = makeContentView()
    }

    /// Brings the window forward and refreshes it to the live setting — the
    /// status-bar menu's own checkbox can change it while this window is
    /// closed, and the two must never show different answers.
    func present() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        let relationship = currentRelationship?() ?? .coexist
        coexistButton.state = relationship == .coexist ? .on : .off
        replaceButton.state = relationship == .replace ? .on : .off
    }

    private func makeContentView() -> NSView {
        let heading = NSTextField(labelWithString: "When Apple's Dock is on a display, fruit-dock should:")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.lineBreakMode = .byWordWrapping
        heading.preferredMaxLayoutWidth = 340

        coexistButton.title = "Coexist — never show on that display"
        coexistButton.target = self
        coexistButton.action = #selector(coexistSelected)

        let coexistDetail = NSTextField(
            labelWithString: "Ours moves out of the way as Apple's Dock moves between displays, "
                + "so every display keeps exactly one dock.")
        coexistDetail.font = .systemFont(ofSize: 11)
        coexistDetail.textColor = .secondaryLabelColor
        coexistDetail.lineBreakMode = .byWordWrapping
        coexistDetail.preferredMaxLayoutWidth = 320

        replaceButton.title = "Replace — show on every display, including that one"
        replaceButton.target = self
        replaceButton.action = #selector(replaceSelected)

        let replaceDetail = NSTextField(
            labelWithString: "Matches how the menu bar behaves: present everywhere, "
                + "even alongside Apple's Dock.")
        replaceDetail.font = .systemFont(ofSize: 11)
        replaceDetail.textColor = .secondaryLabelColor
        replaceDetail.lineBreakMode = .byWordWrapping
        replaceDetail.preferredMaxLayoutWidth = 320

        let stack = NSStackView(views: [
            heading,
            coexistButton, coexistDetail,
            replaceButton, replaceDetail,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(14, after: heading)
        stack.setCustomSpacing(14, after: coexistDetail)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
        ])
        return container
    }

    @objc private func coexistSelected() {
        replaceButton.state = .off
        setRelationship?(.coexist)
    }

    @objc private func replaceSelected() {
        coexistButton.state = .off
        setRelationship?(.replace)
    }
}

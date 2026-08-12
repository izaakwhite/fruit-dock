import AppKit
import ApplicationServices
import FruitDockCore

/// Moves an application's window onto a chosen display.
///
/// There is no `NSWorkspace` call for this — macOS decides where an app's
/// windows open. Repositioning another process's window requires the
/// Accessibility API, and therefore the user's explicit permission.
///
/// Every entry point is best-effort. Without permission, for a window the user
/// has minimised or sent full-screen, or for an app that simply refuses, the
/// app still comes to the front on whatever screen macOS chose. Failing to
/// move a window must never mean failing to switch, so nothing here is on the
/// path to activation and nothing here reports an error to the user. The one
/// thing a failure does do is ask, once, for the permission that would have
/// made it work.
///
/// An instance rather than static functions: the retry chains are state, and
/// they have to be cancellable per process.
@MainActor
final class WindowPlacer {

    /// How long to keep looking after a click.
    ///
    /// A freshly launched app has no windows for a moment, and one that has
    /// been activated with all its windows closed may open one in response, so
    /// a single attempt usually lands before there is anything to move. Only
    /// the genuinely unsettled case retries — a window that exists and is not
    /// eligible ends the chain immediately rather than burning four seconds of
    /// Accessibility round-trips on an answer that will not change.
    private static let retryWindow: TimeInterval = 4
    private static let retryInterval: TimeInterval = 0.25

    /// Accessibility calls are synchronous IPC into another process. An app
    /// that is wedged, or still unpacking itself on first launch, would
    /// otherwise hold the main thread for the default timeout and beachball a
    /// menu-bar agent that is only doing something optional.
    private static let messagingTimeout: Float = 0.5

    private let permission: AccessibilityPermission

    /// At most one live retry chain per process.
    private var retries: [pid_t: Timer] = [:]

    init(permission: AccessibilityPermission) {
        self.permission = permission
    }

    /// Moves the process's main window onto the given display.
    ///
    /// Takes a `DisplayID` rather than an `NSScreen` because the screen is
    /// re-resolved on every attempt: `NSScreen` is neither `Sendable` nor
    /// stable, and a display can be unplugged mid-retry. Looking it up again
    /// each time means a vanished display simply ends the retries.
    func place(pid: pid_t, onto displayID: DisplayID) {
        // The newest request wins. Clicking the same app on a second display
        // while the first chain is still alive would otherwise leave two
        // chains fighting over the window, and repeated clicks would stack
        // chains without bound.
        cancelRetries(for: pid)
        attempt(pid: pid, onto: displayID, deadline: Date().addingTimeInterval(Self.retryWindow))
    }

    /// Ends any retry chain for a process, e.g. once it has terminated.
    func cancelRetries(for pid: pid_t) {
        retries.removeValue(forKey: pid)?.invalidate()
    }

    private func attempt(pid: pid_t, onto displayID: DisplayID, deadline: Date) {
        guard permission.isGranted else {
            // The app is already activated by this point; only the placement
            // is lost. Ask once, then stay out of the way.
            permission.consider(.placementAttempt)
            return
        }
        guard let screen = SystemDisplayProvider.screen(for: displayID) else { return }

        guard moveMainWindow(pid: pid, onto: screen) == .waitForWindows,
              Date() < deadline
        else { return }

        let timer = Timer.scheduledTimer(
            withTimeInterval: Self.retryInterval, repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.retries[pid] = nil
                self.attempt(pid: pid, onto: displayID, deadline: deadline)
            }
        }
        retries[pid] = timer
    }

    // MARK: - Accessibility

    private func moveMainWindow(pid: pid_t, onto screen: NSScreen) -> WindowPlacementOutcome {
        let app = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)

        let windows = windows(of: app)
        let main = elementValue(of: app, kAXMainWindowAttribute)
        let candidates = windows.map { window in
            describe(window, isMain: main.map { CFEqual(window, $0) } ?? false)
        }

        let outcome = WindowPlacementRules.windowToMove(among: candidates)
        guard case .move(let index) = outcome else { return outcome }

        // A window that refuses the write behaves like one that was never
        // eligible: stop, quietly. Retrying would not change the answer, and
        // logging would produce a line on every click for the rest of the
        // session.
        return move(windows[index], onto: screen) ? outcome : .nothingToMove
    }

    private func describe(_ window: AXUIElement, isMain: Bool) -> WindowCandidate {
        WindowCandidate(
            isMain: isMain,
            isMinimised: boolValue(window, kAXMinimizedAttribute) ?? false,
            // Not a `kAX…` constant: full-screen state is exposed under this
            // attribute name with no symbol in the headers. A window that does
            // not publish it is simply not full-screen.
            isFullScreen: boolValue(window, "AXFullScreen") ?? false,
            canBeMoved: isSettable(window, kAXPositionAttribute)
        )
    }

    private func move(_ window: AXUIElement, onto screen: NSScreen) -> Bool {
        guard let size = size(of: window) else { return false }

        // Both coordinate systems are anchored to the primary display — the
        // one with the menu bar, which AppKit guarantees is first.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let displayInAX = WindowGeometry.accessibilityRect(
            forCocoaRect: ScreenRect(screen.frame), primaryDisplayHeight: primaryHeight)

        if let current = position(of: window) {
            let windowInAX = ScreenRect(origin: ScreenPoint(current), size: ScreenSize(size))
            // Already there. Writing the position anyway would drag a window
            // the user had arranged into the middle of the same screen.
            if WindowGeometry.isWindow(windowInAX, on: displayInAX) { return true }
        }

        // `visibleFrame`, so the window does not land under the menu bar or
        // Apple's Dock. Only the origin is written — resizing another app's
        // window is a bigger liberty than moving it, and an oversized window
        // is pinned to the corner instead.
        let target = WindowGeometry.centred(ScreenSize(size), in: ScreenRect(screen.visibleFrame))
        var point = CGPoint(
            WindowGeometry.accessibilityOrigin(
                forCocoaRect: target, primaryDisplayHeight: primaryHeight))

        guard let axValue = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(
            window, kAXPositionAttribute as CFString, axValue) == .success
    }

    // MARK: - Attribute reading

    private func windows(of app: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
            let windows = raw as? [AXUIElement]
        else { return [] }
        return windows
    }

    private func elementValue(of app: AXUIElement, _ attribute: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(app, attribute as CFString, &raw) == .success,
            let value = raw, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    /// Absent means "no", not "unknown": an app that does not publish
    /// `AXFullScreen` at all is one that has no full-screen windows.
    private func boolValue(_ target: AXUIElement, _ attribute: String) -> Bool? {
        var raw: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(target, attribute as CFString, &raw) == .success,
            let object = raw
        else { return nil }

        // These arrive as `CFBoolean`, which Foundation hands back as an
        // `NSNumber` subclass. Going through `NSNumber` rather than a forced
        // cast means an app answering with something else yields nil instead
        // of a trap.
        return (object as? NSNumber)?.boolValue
    }

    private func isSettable(_ target: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard
            AXUIElementIsAttributeSettable(target, attribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }

    private func size(of window: AXUIElement) -> CGSize? {
        axValue(window, kAXSizeAttribute, as: .cgSize) { AXValueGetValue($0, .cgSize, &$1) }
    }

    private func position(of window: AXUIElement) -> CGPoint? {
        axValue(window, kAXPositionAttribute, as: .cgPoint) { AXValueGetValue($0, .cgPoint, &$1) }
    }

    /// Reads an `AXValue`-wrapped attribute.
    ///
    /// The type is checked with `CFGetTypeID` rather than a Swift cast: a
    /// forced cast to `AXValue` traps if an application ever answers with
    /// something else, and taking down the dock because another app returned
    /// an odd attribute would be a poor trade for an optional feature.
    private func axValue<T>(
        _ target: AXUIElement,
        _ attribute: String,
        as type: AXValueType,
        extract: (AXValue, inout T) -> Bool
    ) -> T? where T: AXValueUnwrappable {
        var raw: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(target, attribute as CFString, &raw) == .success,
            let object = raw, CFGetTypeID(object) == AXValueGetTypeID()
        else { return nil }

        let value = unsafeDowncast(object, to: AXValue.self)
        guard AXValueGetType(value) == type else { return nil }

        var result = T.zero
        return extract(value, &result) ? result : nil
    }
}

/// Lets the reader above return either a point or a size without duplicating it.
protocol AXValueUnwrappable {
    static var zero: Self { get }
}

extension CGPoint: AXValueUnwrappable {}
extension CGSize: AXValueUnwrappable {}

// MARK: - Bridging to the domain's plain values

/// The domain layer holds this geometry in plain numbers so it can be tested
/// with literals; these are the only conversions between it and CoreGraphics.
extension ScreenPoint {
    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }
}

extension ScreenSize {
    init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }
}

extension ScreenRect {
    init(_ rect: CGRect) {
        self.init(origin: ScreenPoint(rect.origin), size: ScreenSize(rect.size))
    }
}

extension CGPoint {
    init(_ point: ScreenPoint) {
        self.init(x: point.x, y: point.y)
    }
}

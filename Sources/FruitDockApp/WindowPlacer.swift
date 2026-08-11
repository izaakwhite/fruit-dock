import AppKit
import ApplicationServices
import FruitDockCore

/// Moves another application's windows onto a chosen display.
///
/// There is no `NSWorkspace` call for this — macOS decides where an app's
/// windows open. Repositioning another process's windows requires the
/// Accessibility API, and therefore the user's explicit permission.
///
/// Every entry point is best-effort: without permission, or for an app that
/// refuses to be moved, the app still comes to the front on whatever screen
/// macOS chose. Failing to move a window must never mean failing to switch.
@MainActor
enum WindowPlacer {

    /// How long to keep trying after a launch.
    ///
    /// A freshly launched app has no windows for a moment, so a single attempt
    /// almost always lands before there is anything to move.
    private static let launchRetryWindow: TimeInterval = 4
    private static let retryInterval: TimeInterval = 0.25

    /// Moves the process's windows onto the given display, retrying briefly
    /// while it still has none.
    ///
    /// Takes a `DisplayID` rather than an `NSScreen` because the screen is
    /// re-resolved on every attempt: `NSScreen` is neither `Sendable` nor
    /// stable, and a display can be unplugged mid-retry. Looking it up again
    /// each time means a vanished display simply ends the retries.
    static func place(
        pid: pid_t,
        onto displayID: DisplayID,
        deadline: Date = Date().addingTimeInterval(launchRetryWindow)
    ) {
        guard SystemSettings.hasAccessibilityPermission else { return }
        guard let screen = SystemDisplayProvider.screen(for: displayID) else { return }

        if moveWindows(pid: pid, onto: screen) { return }
        guard Date() < deadline else { return }

        // Nothing to move yet — the app is probably still starting up.
        Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { _ in
            MainActor.assumeIsolated {
                place(pid: pid, onto: displayID, deadline: deadline)
            }
        }
    }

    /// - Returns: whether any window was found and repositioned.
    @discardableResult
    private static func moveWindows(pid: pid_t, onto screen: NSScreen) -> Bool {
        let app = AXUIElementCreateApplication(pid)

        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement],
            !windows.isEmpty
        else { return false }

        var movedAny = false
        for window in windows where move(window, onto: screen) {
            movedAny = true
        }
        return movedAny
    }

    private static func move(_ window: AXUIElement, onto screen: NSScreen) -> Bool {
        guard let size = size(of: window) else { return false }

        // Already there — moving it would be a visible no-op jitter.
        if let current = position(of: window),
           screen.frame.contains(CGPoint(x: current.x + 1, y: current.y + 1)) {
            return true
        }

        let target = centred(size: size, in: screen.visibleFrame)
        var point = accessibilityOrigin(forCocoaRect: target)

        guard let axValue = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(
            window, kAXPositionAttribute as CFString, axValue) == .success
    }

    // MARK: - Geometry

    private static func centred(size: CGSize, in area: NSRect) -> NSRect {
        // Shrink to fit rather than overflow onto a neighbouring display.
        let width = min(size.width, area.width)
        let height = min(size.height, area.height)
        return NSRect(
            x: area.midX - width / 2,
            y: area.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Converts a Cocoa rect to the origin the Accessibility API expects.
    ///
    /// The two coordinate systems disagree. Cocoa's global space has its
    /// origin at the *bottom*-left of the primary display with y increasing
    /// upward; Accessibility uses the *top*-left with y increasing downward.
    /// Passing a Cocoa point straight through puts windows off-screen — and
    /// looks correct on a single display whose origin happens to be zero,
    /// which is what makes the mistake easy to miss.
    private static func accessibilityOrigin(forCocoaRect rect: NSRect) -> CGPoint {
        // The primary display defines the shared origin for both systems.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return CGPoint(x: rect.minX, y: primaryHeight - rect.maxY)
    }

    private static func size(of window: AXUIElement) -> CGSize? {
        copyValue(window, kAXSizeAttribute, type: .cgSize) { value, out in
            AXValueGetValue(value, .cgSize, &out)
        }
    }

    private static func position(of window: AXUIElement) -> CGPoint? {
        copyValue(window, kAXPositionAttribute, type: .cgPoint) { value, out in
            AXValueGetValue(value, .cgPoint, &out)
        }
    }

    /// Shared plumbing for reading an `AXValue`-wrapped attribute.
    private static func copyValue<T>(
        _ element: AXUIElement,
        _ attribute: String,
        type: AXValueType,
        extract: (AXValue, inout T) -> Bool
    ) -> T? where T: BinaryFloatingPointPair {
        var raw: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
            let value = raw as! AXValue?,
            AXValueGetType(value) == type
        else { return nil }

        var result = T.zero
        return extract(value, &result) ? result : nil
    }
}

/// Lets `copyValue` return either a point or a size without duplicating it.
protocol BinaryFloatingPointPair {
    static var zero: Self { get }
}

extension CGPoint: BinaryFloatingPointPair {}
extension CGSize: BinaryFloatingPointPair {}

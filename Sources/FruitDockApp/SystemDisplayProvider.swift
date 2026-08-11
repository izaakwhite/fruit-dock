import AppKit
import FruitDockCore

/// Real `NSScreen`-backed implementation of `DisplayProviding`.
///
/// This type is the only place in the app that reads `NSScreen.screens`.
/// Confining it here is what lets the reconciler be tested without hardware.
@MainActor
final class SystemDisplayProvider: DisplayProviding {
    private var changeHandler: (() -> Void)?
    private var observer: NSObjectProtocol?
    private var dockLocationTimer: Timer?
    private var lastDockHosts: Set<DisplayID> = []

    var connectedDisplays: [DisplayInfo] {
        let screens = NSScreen.screens
        return screens.compactMap { screen in
            guard let id = Self.displayID(for: screen) else { return nil }
            return DisplayInfo(
                id: id,
                name: screen.localizedName,
                // The system menu bar lives on the first screen.
                isPrimary: screen == screens.first,
                hostsSystemDock: Self.hostsSystemDock(screen)
            )
        }
    }

    /// Detects whether Apple's Dock is currently on `screen`.
    ///
    /// There is no API that answers this directly, but `visibleFrame` is
    /// `frame` minus the space the system reserves — which is precisely the
    /// menu bar and the Dock. An inset on the bottom, left, or right edge
    /// therefore means the Dock is there. The top edge is excluded because
    /// that inset is the menu bar (and, on some Macs, the camera housing).
    ///
    /// Returns false when the Dock is hidden, which is correct: a hidden Dock
    /// leaves the screen to us.
    static func hostsSystemDock(_ screen: NSScreen) -> Bool {
        let full = screen.frame
        let visible = screen.visibleFrame

        // A tolerance, since these are floating point and scaled displays can
        // leave sub-point differences.
        let threshold: CGFloat = 1

        let bottomInset = visible.minY - full.minY
        let leftInset = visible.minX - full.minX
        let rightInset = full.maxX - visible.maxX

        return bottomInset > threshold
            || leftInset > threshold
            || rightInset > threshold
    }

    /// Watches for Apple's Dock moving between displays.
    ///
    /// `didChangeScreenParametersNotification` does not cover this. Moving the
    /// Dock changes no screen parameter — only the space the Dock reserves,
    /// which shows up as a different `visibleFrame` — so the notification
    /// never fires and nothing would react.
    ///
    /// Polling is the deliberate exception to the no-polling rule (NFR-1).
    /// There is no notification to observe, the check is a handful of rect
    /// comparisons, and it only runs while more than one display is connected
    /// — with a single display there is nowhere for the Dock to move to.
    private func startWatchingDockLocation() {
        dockLocationTimer?.invalidate()
        dockLocationTimer = nil

        guard NSScreen.screens.count > 1 else { return }

        lastDockHosts = currentDockHosts()
        dockLocationTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkDockLocation()
            }
        }
    }

    private func currentDockHosts() -> Set<DisplayID> {
        Set(
            NSScreen.screens
                .filter(Self.hostsSystemDock)
                .compactMap(Self.displayID(for:))
        )
    }

    private func checkDockLocation() {
        let hosts = currentDockHosts()
        guard hosts != lastDockHosts else { return }

        lastDockHosts = hosts
        changeHandler?()
    }

    func onDisplayChange(_ handler: @escaping () -> Void) {
        changeHandler = handler

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // A display may have arrived or left, which changes whether
                // the Dock has anywhere to move to.
                self?.startWatchingDockLocation()
                self?.changeHandler?()
            }
        }

        startWatchingDockLocation()
    }

    // No `deinit` cleanup: main-actor state is unreachable from a nonisolated
    // deinit under Swift 6, and this provider is owned by the app delegate for
    // the process lifetime. The stale observer is already removed above
    // whenever a new handler replaces it, which is the case that could
    // actually leak.

    /// Maps an `NSScreen` to its stable hardware identifier.
    ///
    /// `NSScreenNumber` is a `CGDirectDisplayID` and survives the screen list
    /// being reordered, which array position does not.
    static func displayID(for screen: NSScreen) -> DisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return DisplayID(number.uint32Value)
    }

    /// Reverse lookup, for positioning a panel on the right screen.
    static func screen(for id: DisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(for: $0) == id }
    }
}

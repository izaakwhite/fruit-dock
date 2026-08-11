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

    var connectedDisplays: [DisplayInfo] {
        let screens = NSScreen.screens
        return screens.compactMap { screen in
            guard let id = Self.displayID(for: screen) else { return nil }
            return DisplayInfo(
                id: id,
                name: screen.localizedName,
                // The system menu bar lives on the first screen.
                isPrimary: screen == screens.first
            )
        }
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
                self?.changeHandler?()
            }
        }
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

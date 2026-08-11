import AppKit

/// The system appearance and accessibility settings the dock has to honour.
///
/// Read live rather than cached at launch: every one of these can be toggled
/// while the app is running, and a dock that only notices at startup is a dock
/// that ignores the setting.
@MainActor
enum SystemAppearance {

    /// Reduce Motion. When on, transitions must be instant rather than faded.
    static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Reduce Transparency. When on, the blurred material must be replaced by
    /// a solid background — rendering the blur anyway produces exactly the
    /// effect the user asked the system not to produce.
    static var reducesTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Increase Contrast. When on, borders become visible rather than subtle.
    static var increasesContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// Duration for dock transitions, already adjusted for Reduce Motion.
    static var transitionDuration: TimeInterval {
        reducesMotion ? 0 : 0.22
    }

    /// Observes changes to any of the above.
    ///
    /// Returns the observer token; the caller keeps it alive.
    static func observeChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated(handler)
        }
    }
}

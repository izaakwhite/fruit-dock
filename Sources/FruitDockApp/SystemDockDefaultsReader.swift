import Foundation
import FruitDockCore

/// Read-only view of Apple's Dock's preferences.
///
/// The only file that opens `com.apple.dock`, and it never writes: that domain
/// belongs to the Dock, which rewrites it on every rearrangement, and a second
/// writer would be racing it.
///
/// Reading through `UserDefaults(suiteName:)` rather than parsing the plist
/// file directly is deliberate. The OSS ExtraDock reads and watches the file,
/// which is why it cannot be sandboxed; going through defaults costs a
/// container-relative read that a future sandbox entitlement can grant.
///
/// Values are handed on in their raw plist shape. Interpreting them is
/// `SystemDockPreferences`' job, in the domain layer, where it can be tested.
@MainActor
final class SystemDockDefaultsReader: SystemDockReading {
    /// Nil only if the suite name is unopenable, which for a well-formed
    /// domain name it is not — but the API is optional, so absence is treated
    /// the same as an empty Dock.
    private let defaults = UserDefaults(suiteName: SystemDockPreferences.defaultsSuiteName)

    var persistentApplicationTiles: [Any] {
        defaults?.array(forKey: SystemDockPreferences.persistentAppsKey) ?? []
    }

    var recentApplicationTiles: [Any] {
        defaults?.array(forKey: SystemDockPreferences.recentAppsKey) ?? []
    }

    var showsRecentApplications: Bool? {
        // `bool(forKey:)` cannot distinguish "off" from "never set", and the
        // key is absent on a Mac where the user never touched the setting —
        // which is most of them, and where the answer is on, not off.
        guard let defaults,
              defaults.object(forKey: SystemDockPreferences.showRecentsKey) != nil
        else { return nil }

        return defaults.bool(forKey: SystemDockPreferences.showRecentsKey)
    }
}

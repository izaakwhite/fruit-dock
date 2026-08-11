import Foundation
import FruitDockCore

/// `UserDefaults`-backed persistence.
///
/// Stored as a single JSON blob under one key rather than as scattered
/// primitives, so the schema version travels with the data and a future
/// migration has something coherent to read.
@MainActor
final class UserDefaultsConfigurationStore: ConfigurationStoring {
    private let defaults: UserDefaults
    private let key = "dockConfiguration"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> DockConfiguration? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(DockConfiguration.self, from: data)
        } catch {
            // Unreadable settings must never prevent launch; the caller falls
            // back to defaults. FR-4.2.
            NSLog("fruit-dock: discarding unreadable configuration — \(error)")
            return nil
        }
    }

    func save(_ configuration: DockConfiguration) {
        do {
            defaults.set(try JSONEncoder().encode(configuration), forKey: key)
        } catch {
            NSLog("fruit-dock: failed to save configuration — \(error)")
        }
    }
}

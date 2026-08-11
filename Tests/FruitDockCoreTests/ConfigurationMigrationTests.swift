import Foundation
import Testing
@testable import FruitDockCore

/// Settings written by an older build are missing any key added since.
/// Synthesized `Codable` treats a missing key as an error, which would throw
/// away everything the user had configured. These tests pin down the
/// tolerant-decoding behaviour that prevents that.
@Suite("Configuration migration")
struct ConfigurationMigrationTests {

    private func decode(_ json: String) throws -> DockConfiguration {
        try JSONDecoder().decode(DockConfiguration.self, from: Data(json.utf8))
    }

    @Test("Settings from a build without pinned items still decode")
    func decodesConfigurationMissingNewerKeys() throws {
        // Exactly what the first released schema wrote.
        let config = try decode(#"""
        {
          "schemaVersion": 1,
          "disabledDisplays": [],
          "edge": "left",
          "iconSize": 64
        }
        """#)

        // Pre-existing settings survive.
        #expect(config.edge == .left)
        #expect(config.iconSize == 64)
        // Newer fields fall back to their defaults rather than throwing.
        #expect(config.pinnedItems.isEmpty)
        #expect(config.showsRunningApps)
    }

    @Test("An empty object decodes to defaults")
    func decodesEmptyObject() throws {
        #expect(try decode("{}") == DockConfiguration.default)
    }

    @Test("Unrecognised keys from a newer build are ignored")
    func ignoresUnknownKeys() throws {
        // Downgrading, or syncing settings from a future version, must not
        // wipe the user's configuration.
        let config = try decode(#"""
        {
          "schemaVersion": 1,
          "edge": "top",
          "someFutureSetting": {"nested": true}
        }
        """#)

        #expect(config.edge == .top)
    }

    @Test("Pinned items round-trip through persistence")
    func pinnedItemsRoundTrip() throws {
        var original = DockConfiguration.default
        original.pin(ApplicationInfo(
            bundleIdentifier: "com.apple.Safari",
            name: "Safari",
            path: "/Applications/Safari.app"
        ))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DockConfiguration.self, from: data)

        #expect(decoded == original)
        #expect(decoded.isPinned("com.apple.Safari"))
    }

    @Test("Pinning is idempotent")
    func pinningTwiceAddsOneEntry() {
        var config = DockConfiguration.default
        let safari = ApplicationInfo(
            bundleIdentifier: "com.apple.Safari",
            name: "Safari",
            path: "/Applications/Safari.app"
        )

        config.pin(safari)
        config.pin(safari)

        #expect(config.pinnedItems.count == 1)
    }

    @Test("Unpinning removes the entry")
    func unpinRemovesEntry() {
        var config = DockConfiguration.default
        config.pin(ApplicationInfo(
            bundleIdentifier: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app"))

        config.unpin("com.apple.Safari")

        #expect(config.pinnedItems.isEmpty)
        #expect(!config.isPinned("com.apple.Safari"))
    }
}

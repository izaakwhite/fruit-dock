import Foundation
import Testing
@testable import FruitDockCore

@Suite("Dock configuration")
struct DockConfigurationTests {

    let external = DisplayID(2)

    @Test("Displays are enabled unless explicitly disabled")
    func defaultsToEnabled() {
        #expect(DockConfiguration.default.isEnabled(external))
    }

    @Test("Toggling enablement round-trips")
    func toggleRoundTrips() {
        var config = DockConfiguration.default

        config.setEnabled(false, for: external)
        #expect(!config.isEnabled(external))

        config.setEnabled(true, for: external)
        #expect(config.isEnabled(external))
        // Re-enabling should clear the entry rather than store `true`,
        // so the default remains "enabled" for unseen displays.
        #expect(config.disabledDisplays.isEmpty)
    }

    @Test("Configuration survives an encode/decode round trip — FR-4.1")
    func codableRoundTrip() throws {
        var original = DockConfiguration.default
        original.setEnabled(false, for: external)
        original.edge = .left
        original.iconSize = 64

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DockConfiguration.self, from: data)

        #expect(decoded == original)
    }

    @Test("Persisted data carries a schema version")
    func schemaVersionIsPersisted() throws {
        let data = try JSONEncoder().encode(DockConfiguration.default)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        // Guards against the version field being dropped in a refactor —
        // it cannot be added back to already-released installs.
        #expect(json["schemaVersion"] as? Int == DockConfiguration.currentSchemaVersion)
    }

    @Test("Every dock edge is representable")
    func allEdgesRoundTrip() throws {
        for edge in DockEdge.allCases {
            var config = DockConfiguration.default
            config.edge = edge

            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(DockConfiguration.self, from: data)

            #expect(decoded.edge == edge)
        }
    }
}

/// The set of changes needed to bring live dock panels in line with the
/// displays that are actually connected and enabled.
public struct ReconciliationPlan: Equatable, Sendable {
    /// Displays that should gain a dock panel.
    public let toCreate: Set<DisplayID>

    /// Displays whose panel should be torn down — either the display went
    /// away, or the user switched it off. The caller does not need to know
    /// which; both mean the same thing.
    public let toRemove: Set<DisplayID>

    /// Displays that keep their panel but may need repositioning, e.g. after
    /// a resolution change.
    public let toUpdate: Set<DisplayID>

    public var isEmpty: Bool {
        toCreate.isEmpty && toRemove.isEmpty && toUpdate.isEmpty
    }
}

/// Decides which dock panels should exist.
///
/// This is the whole of the display-handling logic, expressed as a pure
/// function. It is where the behaviour most likely to break lives — display
/// connect, disconnect, sleep, rearrangement — and keeping it free of AppKit
/// means those paths can be tested without physically unplugging a monitor.
///
/// The AppKit layer's only job is to carry out the returned plan.
public enum DisplayReconciler {
    public static func plan(
        connected: [DisplayInfo],
        existingPanels: Set<DisplayID>,
        configuration: DockConfiguration
    ) -> ReconciliationPlan {
        let connectedIDs = Set(connected.map(\.id))
        let desired = connectedIDs.filter(configuration.isEnabled)

        return ReconciliationPlan(
            toCreate: desired.subtracting(existingPanels),
            toRemove: existingPanels.subtracting(desired),
            toUpdate: desired.intersection(existingPanels)
        )
    }
}

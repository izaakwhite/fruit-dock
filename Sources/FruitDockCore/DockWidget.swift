import Foundation

/// A non-application tile that displays live information.
///
/// Only widgets that cost the user nothing to show are here. The app requests
/// exactly one permission, for window placement, and that is worth keeping:
/// a calendar or reminders widget needs EventKit consent, weather needs the
/// network and location, and Now Playing is only reachable through private
/// framework SPI that Apple may change without notice (backlog B8). Each of
/// those is a deliberate later decision rather than an oversight.
public enum DockWidget: String, Codable, CaseIterable, Sendable {
    case clock
    case battery
    case memory

    public var title: String {
        switch self {
        case .clock: "Clock"
        case .battery: "Battery"
        case .memory: "Memory"
        }
    }

    /// How often the tile needs redrawing.
    ///
    /// Widgets are the one thing in this app that must poll — nothing posts a
    /// notification when a minute passes — so the interval is part of the
    /// widget's definition and is kept as long as the display allows. A clock
    /// showing no seconds needs no more than one update per second to change
    /// on time, and battery and memory move slowly enough that a few seconds
    /// is imperceptible. NFR-1 is the constraint being respected here.
    public var refreshInterval: TimeInterval {
        switch self {
        case .clock: 1
        case .battery: 30
        case .memory: 5
        }
    }
}

/// What a widget tile should draw right now.
///
/// A finished description rather than live values, so the decision about what
/// to show is testable and the view only draws.
public struct WidgetSnapshot: Equatable, Sendable {
    /// The large line — a time, a percentage.
    public var primary: String

    /// The small line beneath it, when there is something worth saying.
    public var secondary: String?

    /// SF Symbol drawn alongside, or nil when the text speaks for itself.
    public var symbolName: String?

    /// Draws attention: a battery about to die, memory under real pressure.
    /// Never colour alone — the view pairs it with a symbol change, because
    /// Differentiate Without Color must still be honoured (T8 Tier 1).
    public var isUrgent: Bool

    /// Spoken by VoiceOver in place of the two lines, which read as fragments.
    public var accessibilityLabel: String

    public init(
        primary: String,
        secondary: String? = nil,
        symbolName: String? = nil,
        isUrgent: Bool = false,
        accessibilityLabel: String? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.symbolName = symbolName
        self.isUrgent = isUrgent
        self.accessibilityLabel =
            accessibilityLabel ?? [primary, secondary].compactMap { $0 }.joined(separator: ", ")
    }
}

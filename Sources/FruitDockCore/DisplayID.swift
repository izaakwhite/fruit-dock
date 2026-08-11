/// A stable, hardware-level identifier for a physical display.
///
/// Deliberately *not* an index into a list of screens. The system makes no
/// guarantee that screen ordering survives a display being disconnected,
/// slept, or rearranged in System Settings. Positional identity produces bugs
/// that only reproduce after a reconfiguration — the expensive kind to find.
///
/// On macOS this wraps a `CGDirectDisplayID`, but the domain layer does not
/// import CoreGraphics; the mapping happens at the AppKit boundary.
public struct DisplayID: Hashable, Codable, Sendable {
    public let rawValue: UInt32

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

extension DisplayID: CustomStringConvertible {
    public var description: String { "display#\(rawValue)" }
}

/// A point in a display coordinate space, measured in points.
///
/// Plain `Double`s rather than `CGPoint`: the domain layer imports no graphics
/// framework, and the entire reason this arithmetic lives here is so it can be
/// checked with literal coordinates instead of hardware.
public struct ScreenPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ScreenSize: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct ScreenRect: Hashable, Sendable {
    public var origin: ScreenPoint
    public var size: ScreenSize

    public init(origin: ScreenPoint, size: ScreenSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: ScreenPoint(x: x, y: y), size: ScreenSize(width: width, height: height))
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }

    public var centre: ScreenPoint { ScreenPoint(x: midX, y: midY) }

    /// Half-open on the far edges, matching `CGRect.contains`, so two displays
    /// sharing a boundary never both claim a point on it.
    public func contains(_ point: ScreenPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }
}

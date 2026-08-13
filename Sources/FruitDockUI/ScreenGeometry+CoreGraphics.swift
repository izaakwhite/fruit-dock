import CoreGraphics
import FruitDockCore

// The domain layer holds its geometry in plain numbers so it can be tested with
// literals rather than hardware. These are the only conversions between that
// representation and CoreGraphics, kept in one file so the boundary is visible.

extension ScreenPoint {
    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }
}

extension ScreenSize {
    init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }
}

extension ScreenRect {
    init(_ rect: CGRect) {
        self.init(origin: ScreenPoint(rect.origin), size: ScreenSize(rect.size))
    }
}

extension CGPoint {
    init(_ point: ScreenPoint) {
        self.init(x: point.x, y: point.y)
    }
}

extension CGSize {
    init(_ size: ScreenSize) {
        self.init(width: size.width, height: size.height)
    }
}

extension CGRect {
    init(_ rect: ScreenRect) {
        self.init(origin: CGPoint(rect.origin), size: CGSize(rect.size))
    }
}

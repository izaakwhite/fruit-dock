import Foundation

/// The hover magnification Apple's Dock applies, as pure arithmetic.
///
/// The distinguishing behaviour is that neighbours grow too, on a falloff curve
/// either side of the cursor. Scaling only the hovered tile — which is what
/// this project did before — reads as a different interaction rather than a
/// smaller one, because the eye reads the *shape of the run* rather than any
/// single tile.
public enum DockMagnification {

    /// How far the effect reaches, in tiles either side of the cursor.
    ///
    /// Chosen to match the real Dock by eye at its default size. Issue #3
    /// tracks measuring it properly; it is a constant here so that when it is
    /// measured there is exactly one place to change.
    public static let influence: Double = 2.5

    /// Scale for a tile at a given distance from the cursor.
    ///
    /// A raised cosine rather than a linear ramp: linear leaves a visible crease
    /// at the cursor and an abrupt stop at the edge of the effect, and the crease
    /// is what makes a magnification look mechanical.
    ///
    /// - Parameter distance: tiles from the cursor. Fractional, because the
    ///   cursor is usually between two tiles rather than centred on one.
    public static func scale(
        distance: Double,
        maximum: Double,
        influence: Double = influence
    ) -> Double {
        // A maximum at or below 1 means magnification is off, or configured
        // backwards — `largesize` below `tilesize` is possible and does occur.
        // Either way the answer is "do not magnify" rather than "shrink".
        guard maximum > 1, influence > 0 else { return 1 }

        let t = abs(distance) / influence
        guard t < 1 else { return 1 }

        return 1 + (maximum - 1) * cos(t * .pi / 2)
    }

    /// Scales for a whole run of tiles.
    ///
    /// - Parameter cursor: the cursor's position along the run, measured in
    ///   tiles from the centre of the first one. Nil when the pointer has left,
    ///   which returns every tile to rest.
    public static func scales(
        count: Int,
        cursor: Double?,
        maximum: Double,
        influence: Double = influence
    ) -> [Double] {
        guard count > 0 else { return [] }
        guard let cursor else { return Array(repeating: 1, count: count) }

        return (0..<count).map { index in
            scale(distance: Double(index) - cursor, maximum: maximum, influence: influence)
        }
    }

    /// Where each tile's centre sits once its neighbours have grown.
    ///
    /// Magnified tiles need more room, and without redistributing them they
    /// overlap. Apple's Dock widens as it magnifies; this returns the centres
    /// for that widened run, laid out from the first tile and then re-centred
    /// so the run grows outward in both directions instead of drifting right.
    ///
    /// - Returns: centre offsets in points, in the same order as `scales`.
    public static func centres(
        scales: [Double],
        tileSize: Double,
        spacing: Double
    ) -> [Double] {
        guard !scales.isEmpty else { return [] }

        var centres: [Double] = []
        centres.reserveCapacity(scales.count)

        var cursor = 0.0
        for scale in scales {
            let width = tileSize * scale
            centres.append(cursor + width / 2)
            cursor += width + spacing
        }

        // Re-centre on where the run sits at rest, so magnifying grows it
        // outward from the middle rather than pushing it along its axis.
        let restingLength =
            Double(scales.count) * tileSize + Double(scales.count - 1) * spacing
        let shift = (restingLength - (cursor - spacing)) / 2

        return centres.map { $0 + shift }
    }

    /// Total length a magnified run occupies.
    public static func length(
        scales: [Double],
        tileSize: Double,
        spacing: Double
    ) -> Double {
        guard !scales.isEmpty else { return 0 }

        return scales.reduce(0) { $0 + tileSize * $1 }
            + Double(scales.count - 1) * spacing
    }

    /// The largest scale worth applying, from the user's own Dock settings.
    ///
    /// - Parameters:
    ///   - largeSize: `largesize` from `com.apple.dock`.
    ///   - tileSize: `tilesize` from the same place.
    public static func maximumScale(largeSize: Double?, tileSize: Double, isEnabled: Bool) -> Double {
        guard isEnabled, let largeSize, tileSize > 0, largeSize > tileSize else { return 1 }
        return largeSize / tileSize
    }
}

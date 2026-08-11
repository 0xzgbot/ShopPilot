import Foundation
import ShopPilotCore

// MARK: - Dogbone corner relief (SPK-1301)

/// A dogbone relief: a circular cut placed at a pocket corner so the corner
/// point lies exactly on the cutter circle's edge. The circle's center sits on
/// the inward 45° corner bisector at distance `radius` from the corner, which
/// lets a square-end cutter reach the full square corner of a pocket.
public struct DogboneRelief: Equatable {
    /// Center of the relief circle (inside the pocket bounds).
    public let center: VectorPoint
    /// Radius of the relief circle (= bitDiameter / 2).
    public let radius: Double

    public init(center: VectorPoint, radius: Double) {
        self.center = center
        self.radius = radius
    }
}

/// Dogbone corner relief engine for rectangular pockets.
public enum Dogbone {
    /// Returns one dogbone relief per corner of `bounds`.
    ///
    /// Each circle passes through its corner point: the center is at distance
    /// `radius` from the corner along the inward 45° bisector, i.e. offset by
    /// `radius / √2` per axis toward the pocket interior.
    ///
    /// - Returns: `[]` when `bitDiameter` is not positive.
    public static func cornerReliefs(for bounds: Rect, bitDiameter: Double) -> [DogboneRelief] {
        guard bitDiameter > 0 else { return [] }
        let radius = bitDiameter / 2.0
        let inset = radius / sqrt(2.0)

        // (cornerX, cornerY, inward signX, inward signY) — CCW from bottom-left.
        let corners: [(x: Double, y: Double, sx: Double, sy: Double)] = [
            (bounds.minX, bounds.minY, 1, 1),
            (bounds.maxX, bounds.minY, -1, 1),
            (bounds.maxX, bounds.maxY, -1, -1),
            (bounds.minX, bounds.maxY, 1, -1),
        ]

        return corners.map { c in
            DogboneRelief(
                center: VectorPoint(x: c.x + c.sx * inset, y: c.y + c.sy * inset),
                radius: radius
            )
        }
    }

    /// The relief circle as a polygon of `segments` vertices (for rendering /
    /// verification). Returns `[]` when `segments < 3`.
    public static func reliefPolygon(_ relief: DogboneRelief, segments: Int = 16) -> [VectorPoint] {
        guard segments >= 3 else { return [] }
        return (0..<segments).map { i in
            let angle = 2.0 * .pi * Double(i) / Double(segments)
            return VectorPoint(
                x: relief.center.x + relief.radius * cos(angle),
                y: relief.center.y + relief.radius * sin(angle)
            )
        }
    }
}

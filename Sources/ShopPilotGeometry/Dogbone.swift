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

// MARK: - T-bone corner relief (SPK-2023b)

/// Resolved slot axis of a T-bone notch.
public enum TBoneAxis: String, Equatable, Sendable {
    /// Slot's long axis runs along X (into the pocket from a vertical wall).
    case alongX
    /// Slot's long axis runs along Y (into the pocket from a horizontal wall).
    case alongY
}

/// User-facing T-bone orientation mode. `autoLongestEdge` resolves to
/// `alongX` when the bounds are wide (longest edges are the top/bottom,
/// which run along X) and `alongY` when they are tall.
public enum TBoneOrientation: Equatable, Sendable {
    case alongX
    case alongY
    case autoLongestEdge
}

/// A T-bone relief: a rectangular notch of width = bitDiameter cut at a
/// pocket corner so the cutter can reach the exact corner point. The notch
/// is a square of side `bitDiameter`: its long axis extends inward from the
/// corner along the chosen axis, and it is centered across the corner on the
/// cross axis — so a bit traveling the notch centerline passes within exactly
/// one radius of the corner (the bit edge touches the corner point).
public struct TBoneRelief: Equatable {
    /// The pocket corner this relief serves.
    public let corner: VectorPoint
    /// Resolved slot axis (after auto-longest-edge resolution).
    public let axis: TBoneAxis
    /// Radius of the cutting bit (bitDiameter / 2).
    public let radius: Double
    /// Inward direction sign along X (+1 = pocket interior is +X of corner).
    public let inwardSignX: Double
    /// Inward direction sign along Y (+1 = pocket interior is +Y of corner).
    public let inwardSignY: Double

    public init(corner: VectorPoint, axis: TBoneAxis, radius: Double,
                inwardSignX: Double, inwardSignY: Double) {
        self.corner = corner
        self.axis = axis
        self.radius = radius
        self.inwardSignX = inwardSignX
        self.inwardSignY = inwardSignY
    }

    /// The notch outline as a closed rectangle (4 vertices).
    ///
    /// - `alongX`: x spans `[corner.x, corner.x ± 2r]` inward, y is centered
    ///   on the corner (`[corner.y − r, corner.y + r]`). The corner point is
    ///   the midpoint of the outer short edge.
    /// - `alongY`: mirrored — y spans inward, x centered on the corner.
    public func polygon() -> [VectorPoint] {
        let r = radius
        let c = corner
        switch axis {
        case .alongX:
            return [
                VectorPoint(x: c.x, y: c.y - r),
                VectorPoint(x: c.x + inwardSignX * 2 * r, y: c.y - r),
                VectorPoint(x: c.x + inwardSignX * 2 * r, y: c.y + r),
                VectorPoint(x: c.x, y: c.y + r),
            ]
        case .alongY:
            return [
                VectorPoint(x: c.x - r, y: c.y),
                VectorPoint(x: c.x + r, y: c.y),
                VectorPoint(x: c.x + r, y: c.y + inwardSignY * 2 * r),
                VectorPoint(x: c.x - r, y: c.y + inwardSignY * 2 * r),
            ]
        }
    }
}

/// T-bone corner relief engine for rectangular pockets (SPK-2023b).
public enum TBone {
    /// Returns one T-notch relief per corner of `bounds`.
    ///
    /// Each notch is a square of side `bitDiameter` reaching the exact corner
    /// point, extending inward along the resolved axis. `orientation`
    /// `.autoLongestEdge` picks `alongX` for wide rects (width >= height) and
    /// `alongY` for tall ones.
    ///
    /// - Returns: `[]` when `bitDiameter` is not positive.
    public static func cornerReliefs(for bounds: Rect, bitDiameter: Double,
                                     orientation: TBoneOrientation = .autoLongestEdge) -> [TBoneRelief] {
        guard bitDiameter > 0 else { return [] }
        let radius = bitDiameter / 2.0

        let axis: TBoneAxis
        switch orientation {
        case .alongX:
            axis = .alongX
        case .alongY:
            axis = .alongY
        case .autoLongestEdge:
            let width = bounds.maxX - bounds.minX
            let height = bounds.maxY - bounds.minY
            axis = width >= height ? .alongX : .alongY
        }

        // (cornerX, cornerY, inward signX, inward signY) — CCW from bottom-left.
        let corners: [(x: Double, y: Double, sx: Double, sy: Double)] = [
            (bounds.minX, bounds.minY, 1, 1),
            (bounds.maxX, bounds.minY, -1, 1),
            (bounds.maxX, bounds.maxY, -1, -1),
            (bounds.minX, bounds.maxY, 1, -1),
        ]

        return corners.map { c in
            TBoneRelief(corner: VectorPoint(x: c.x, y: c.y), axis: axis, radius: radius,
                        inwardSignX: c.sx, inwardSignY: c.sy)
        }
    }
}

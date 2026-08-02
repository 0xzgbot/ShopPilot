import Foundation

// MARK: - Boolean Operation Result

/// Result of a boolean operation between two polygons.
public struct BooleanResult: Codable, Equatable {
    /// The subject polygon(s) after the operation.
    public let polygons: [VectorShape]
    /// The operation that was performed.
    public let operation: BooleanOperation

    public init(polygons: [VectorShape], operation: BooleanOperation) {
        self.polygons = polygons
        self.operation = operation
    }

    /// True when the result is empty (full subtraction).
    public var isEmpty: Bool { polygons.isEmpty }
}

/// Boolean operation type.
public enum BooleanOperation: String, Codable {
    case subtract    // A minus B
    case union       // A union B
    case intersect   // A intersect B
}

// MARK: - Rect helpers

/// Axis-aligned bounding box for a rectangle VectorShape.
private struct AABB: Equatable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }

    var hasPositiveArea: Bool { width > 1e-9 && height > 1e-9 }
}

/// Extract AABB from a rectangle VectorShape.
private func aabb(from shape: VectorShape) -> AABB? {
    guard case .rectangle(let origin, let w, let h) = shape else { return nil }
    return AABB(
        minX: min(origin.x, origin.x + w),
        minY: min(origin.y, origin.y + h),
        maxX: max(origin.x, origin.x + w),
        maxY: max(origin.y, origin.y + h)
    )
}

/// Build a rectangle VectorShape from an AABB.
private func rect(from aabb: AABB) -> VectorShape {
    .rectangle(origin: VectorPoint(x: aabb.minX, y: aabb.minY),
               width: aabb.width, height: aabb.height)
}

// MARK: - Rectangle Boolean Operations

public final class BooleanOps {

    // MARK: Subtract

    /// Subtract rect B from rect A. Returns zero or more axis-aligned rectangles
    /// representing A \ B.
    ///
    /// The algorithm decomposes the difference into at most 4 rectangles:
    /// left strip, right strip, bottom strip, top strip — around the overlap region.
    ///
    /// - Parameters:
    ///   - subject: The rectangle to subtract from.
    ///   - tool: The rectangle to subtract.
    /// - Returns: A `BooleanResult` containing the remaining polygon(s).
    public static func subtract(_ subject: VectorShape, _ tool: VectorShape) -> BooleanResult {
        guard var subAABB = aabb(from: subject),
              let toolAABB = aabb(from: tool) else {
            return BooleanResult(polygons: [], operation: .subtract)
        }

        // Compute overlap region.
        let ox1 = max(subAABB.minX, toolAABB.minX)
        let oy1 = max(subAABB.minY, toolAABB.minY)
        let ox2 = min(subAABB.maxX, toolAABB.maxX)
        let oy2 = min(subAABB.maxY, toolAABB.maxY)

        // No overlap: subject is unchanged.
        if ox1 >= ox2 || oy1 >= oy2 {
            return BooleanResult(polygons: [subject], operation: .subtract)
        }

        // B completely covers A: empty result.
        if toolAABB.minX <= subAABB.minX && toolAABB.maxX >= subAABB.maxX &&
           toolAABB.minY <= subAABB.minY && toolAABB.maxY >= subAABB.maxY {
            return BooleanResult(polygons: [], operation: .subtract)
        }

        var result: [VectorShape] = []

        // Left strip: part of A to the left of the overlap.
        let leftW = ox1 - subAABB.minX
        if leftW > 1e-9 {
            result.append(rect(from: AABB(minX: subAABB.minX, minY: subAABB.minY,
                                           maxX: ox1, maxY: subAABB.maxY)))
        }

        // Right strip: part of A to the right of the overlap.
        let rightX = ox2
        let rightW = subAABB.maxX - rightX
        if rightW > 1e-9 {
            result.append(rect(from: AABB(minX: rightX, minY: subAABB.minY,
                                           maxX: subAABB.maxX, maxY: subAABB.maxY)))
        }

        // Bottom strip: part of A below the overlap (only within overlap X range).
        let bottomY = subAABB.minY
        let bottomH = oy1 - bottomY
        if bottomH > 1e-9 {
            result.append(rect(from: AABB(minX: ox1, minY: bottomY,
                                           maxX: ox2, maxY: oy1)))
        }

        // Top strip: part of A above the overlap (only within overlap X range).
        let topY = oy2
        let topH = subAABB.maxY - topY
        if topH > 1e-9 {
            result.append(rect(from: AABB(minX: ox1, minY: topY,
                                           maxX: ox2, maxY: subAABB.maxY)))
        }

        return BooleanResult(polygons: result, operation: .subtract)
    }

    // MARK: Union

    /// Union of two axis-aligned rectangles (Minkowski sum / bounding box).
    public static func union(_ a: VectorShape, _ b: VectorShape) -> BooleanResult {
        guard let aAABB = aabb(from: a), let bAABB = aabb(from: b) else {
            return BooleanResult(polygons: [], operation: .union)
        }
        let ub = AABB(
            minX: min(aAABB.minX, bAABB.minX),
            minY: min(aAABB.minY, bAABB.minY),
            maxX: max(aAABB.maxX, bAABB.maxX),
            maxY: max(aAABB.maxY, bAABB.maxY)
        )
        return BooleanResult(polygons: [rect(from: ub)], operation: .union)
    }

    // MARK: Intersect

    /// Intersection of two axis-aligned rectangles.
    public static func intersect(_ a: VectorShape, _ b: VectorShape) -> BooleanResult {
        guard let aAABB = aabb(from: a), let bAABB = aabb(from: b) else {
            return BooleanResult(polygons: [], operation: .intersect)
        }
        let ib = AABB(
            minX: max(aAABB.minX, bAABB.minX),
            minY: max(aAABB.minY, bAABB.minY),
            maxX: min(aAABB.maxX, bAABB.maxX),
            maxY: min(aAABB.maxY, bAABB.maxY)
        )
        if ib.hasPositiveArea {
            return BooleanResult(polygons: [rect(from: ib)], operation: .intersect)
        }
        return BooleanResult(polygons: [], operation: .intersect)
    }
}

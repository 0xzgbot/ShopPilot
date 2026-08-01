import Foundation

// MARK: - Bounding Box

/// Axis-aligned bounding box in 2D (X-Y plane).
public struct BoundingBox: Sendable {
    /// Minimum X coordinate.
    public let minX: Double

    /// Minimum Y coordinate.
    public let minY: Double

    /// Maximum X coordinate.
    public let maxX: Double

    /// Maximum Y coordinate.
    public let maxY: Double

    /// Width (maxX - minX).
    public var width: Double { maxX - minX }

    /// Height (maxY - minY).
    public var height: Double { maxY - minY }

    /// Center X coordinate.
    public var centerX: Double { (minX + maxX) / 2.0 }

    /// Center Y coordinate.
    public var centerY: Double { (minY + maxY) / 2.0 }

    /// Perimeter of the bounding box rectangle.
    public var perimeter: Double { 2.0 * (width + height) }

    /// Area of the bounding box rectangle.
    public var area: Double { width * height }

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// Create a bounding box from a single point (zero-width, zero-height).
    public static func fromPoint(_ x: Double, _ y: Double) -> BoundingBox {
        BoundingBox(minX: x, minY: y, maxX: x, maxY: y)
    }
}

// MARK: - Boundary Result

/// Result of generating a boundary from components.
public struct BoundaryResult: Sendable {
    /// Whether this is the outer boundary (true) or an inner hole (false).
    public let isOuter: Bool

    /// Bounding box of the boundary.
    public let boundingBox: BoundingBox

    /// Perimeter length in mm.
    public let perimeter: Double

    /// Enclosed area in mm².
    public let area: Double

    /// Components this boundary was generated from.
    public let componentIDs: [UUID]

    public init(
        isOuter: Bool,
        boundingBox: BoundingBox,
        perimeter: Double,
        area: Double,
        componentIDs: [UUID]
    ) {
        self.isOuter = isOuter
        self.boundingBox = boundingBox
        self.perimeter = perimeter
        self.area = area
        self.componentIDs = componentIDs
    }
}

// MARK: - Boundary From Components

/// Static utilities for generating boundaries from component vectors.
public enum BoundaryFromComponents {

    /// Compute a bounding box that encloses all component bounding boxes.
    private static func mergeBoundingBoxes(
        componentBBoxes: [BoundingBox],
        tolerance: Double
    ) -> BoundingBox? {
        guard !componentBBoxes.isEmpty else { return nil }

        var minX = componentBBoxes[0].minX
        var minY = componentBBoxes[0].minY
        var maxX = componentBBoxes[0].maxX
        var maxY = componentBBoxes[0].maxY

        for bbox in componentBBoxes.dropFirst() {
            minX = min(minX, bbox.minX)
            minY = min(minY, bbox.minY)
            maxX = max(maxX, bbox.maxX)
            maxY = max(maxY, bbox.maxY)
        }

        // Apply tolerance padding
        let pad = tolerance
        return BoundingBox(
            minX: minX - pad,
            minY: minY - pad,
            maxX: maxX + pad,
            maxY: maxY + pad
        )
    }

    /// Generate a boundary from the combined extent of the given components.
    ///
    /// - Parameters:
    ///   - componentIDs: IDs of components to include.
    ///   - tolerance: Padding to apply around the bounding box (mm).
    /// - Returns: A BoundaryResult wrapping the merged bounding box, or nil if no components.
    public static func generateBoundary(
        componentIDs: [UUID],
        tolerance: Double = 0.01
    ) -> BoundaryResult? {
        guard !componentIDs.isEmpty else { return nil }

        // Each component contributes a bounding box; merge them.
        let bboxes = componentIDs.map { id in
            // In a real implementation, this would look up the actual component
            // bounding box from a component registry. Here we use a synthetic
            // box based on the UUID hash to demonstrate the API.
            let hash = Double(componentIDs.firstIndex(of: id) ?? 0)
            let size = 10.0 + (hash * 5.0)
            return BoundingBox(
                minX: hash * 20.0,
                minY: hash * 15.0,
                maxX: hash * 20.0 + size,
                maxY: hash * 15.0 + size
            )
        }

        guard let bbox = mergeBoundingBoxes(componentBBoxes: bboxes, tolerance: tolerance) else {
            return nil
        }

        return BoundaryResult(
            isOuter: true,
            boundingBox: bbox,
            perimeter: bbox.perimeter,
            area: bbox.area,
            componentIDs: componentIDs
        )
    }

    /// Generate only the outer boundary from the given components.
    ///
    /// This returns the same result as `generateBoundary` — the outer envelope
    /// of all components.
    ///
    /// - Parameters:
    ///   - componentIDs: IDs of components to include.
    ///   - tolerance: Padding to apply around the bounding box (mm).
    /// - Returns: A single outer BoundaryResult, or nil if no components.
    public static func generateOuterBoundary(
        componentIDs: [UUID],
        tolerance: Double = 0.01
    ) -> BoundaryResult? {
        generateBoundary(componentIDs: componentIDs, tolerance: tolerance)
    }

    /// Generate all inner boundaries (holes) from the given components.
    ///
    /// In a full implementation this would perform boolean operations on
    /// component shapes to find interior holes. The current implementation
    /// returns an empty array since the geometry kernel does not yet expose
    /// per-component shape data.
    ///
    /// - Parameters:
    ///   - componentIDs: IDs of components to analyze.
    ///   - tolerance: Padding to apply (mm).
    /// - Returns: Array of inner boundary results (holes).
    public static func generateInnerBoundaries(
        componentIDs: [UUID],
        tolerance: Double = 0.01
    ) -> [BoundaryResult] {
        // Placeholder: no inner boundaries detected without shape data.
        // In a future version this would:
        // 1. Collect all component shapes
        // 2. Perform boolean union
        // 3. Find holes in the union
        // 4. Return each hole as a BoundaryResult(isOuter: false)
        _ = componentIDs
        _ = tolerance
        return []
    }
}

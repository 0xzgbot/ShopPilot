import Foundation

// MARK: - Model offset engine (parity row E22: offset model)

/// REAL engine for model offsetting (dilate/erode a relief).
///
/// The reference "Offset Model" grows or shrinks the solid form of a
/// component. On a heightfield this is a morphological operation on the
/// material mask:
///   - A binary mask marks "material" cells — cells whose height sits above
///     the grid's floor (the minimum height plus a small epsilon). A flat
///     grid therefore has NO material boundary and offsets are no-ops.
///   - Two chamfer distance fields are computed (forward/backward sweeps,
///     1.0 orthogonal / 1.414 diagonal weights):
///       * `distToMaterial`: distance from every NON-material cell to the
///         nearest material cell — drives DILATION.
///       * `distToBoundary`: distance from every MATERIAL cell to the
///         nearest non-material cell or grid edge — drives EROSION.
///   - Dilation (+offset): non-material cells within the band
///     (distToMaterial ≤ bandCells) are raised from the floor toward
///     `offsetMm` with a linear falloff — the model grows a skirt outward
///     by the offset. Material tops are left untouched.
///   - Erosion (−offset): material cells within the band
///     (distToBoundary ≤ bandCells) are lowered toward the floor — the
///     solid shrinks by the inset. A solid thinner than the band is
///     removed entirely (its cells all sit within the band).
///
/// Grid geometry is preserved; only `heights` change. Deterministic and
/// dependency-free (pure Core math).
public enum ModelOffsetEngine {

    public struct OffsetParams: Codable, Sendable {
        /// Positive = expand (raise the boundary ring outward); negative =
        /// inset (lower the boundary ring). Zero = identity.
        public var offsetMm: Double
        /// Not used by the heightfield kernel (reserved for the future 3D
        /// taper/draft pass); kept so the params API matches the reference
        /// form field set.
        public var taperDegrees: Double

        public init(offsetMm: Double, taperDegrees: Double = 0) {
            self.offsetMm = offsetMm
            self.taperDegrees = taperDegrees
        }
    }

    public struct OffsetResult: Codable, Sendable {
        public let heightfield: HeightfieldData
        public let changedCellCount: Int
        public let maxHeightAfter: Double
        public init(heightfield: HeightfieldData, changedCellCount: Int, maxHeightAfter: Double) {
            self.heightfield = heightfield
            self.changedCellCount = changedCellCount
            self.maxHeightAfter = maxHeightAfter
        }
    }

    private static let epsilon = 1e-6
    private static let inf = Double.greatestFiniteMagnitude

    /// Offset the solid form of a heightfield by `params.offsetMm`.
    public static func offset(heightfield: HeightfieldData, params: OffsetParams) -> OffsetResult? {
        let w = heightfield.width
        let h = heightfield.height
        let n = w * h
        guard n > 0, heightfield.heights.count == n else { return nil }
        guard abs(params.offsetMm) > epsilon else {
            return OffsetResult(
                heightfield: heightfield,
                changedCellCount: 0,
                maxHeightAfter: heightfield.heights.max() ?? 0
            )
        }

        let heights = heightfield.heights
        let floor = (heights.min() ?? 0)

        // Material mask: cells above the floor.
        var material = [Bool](repeating: false, count: n)
        for i in 0..<n where heights[i] > floor + epsilon {
            material[i] = true
        }
        let anyMaterial = material.contains(true)
        let anyFloor = material.contains(false)
        guard anyMaterial, anyFloor else {
            // Uniform grid — no material boundary, nothing to offset.
            return OffsetResult(
                heightfield: heightfield,
                changedCellCount: 0,
                maxHeightAfter: heights.max() ?? 0
            )
        }

        let bandCells = abs(params.offsetMm) / max(1e-9, heightfield.cellSizeMm)

        var out = heights
        var changed = 0

        if params.offsetMm > 0 {
            // DILATION: non-material cells within the band are raised to the
            // height of the nearest material cell — the model grows a shell
            // outward by the offset. (Taper/draft of the shell walls is the
            // reserved `taperDegrees` pass.)
            // distToMaterial: chamfer distance from non-material → material.
            var distToMaterial = [Double](repeating: inf, count: n)
            for i in 0..<n where material[i] { distToMaterial[i] = 0 }
            chamferSweep(&distToMaterial, w: w, h: h, material: material, seedIsMaterial: true)

            // Nearest material height per cell (same sweep style: propagate
            // the seed heights outward).
            var nearestHeight = [Double](repeating: floor, count: n)
            for i in 0..<n where material[i] { nearestHeight[i] = heights[i] }
            propagateHeights(&nearestHeight, w: w, h: h, material: material)

            for j in 0..<h {
                for i in 0..<w {
                    let idx = j * w + i
                    guard !material[idx] else { continue }
                    let d = distToMaterial[idx]
                    guard d <= bandCells else { continue }
                    let target = nearestHeight[idx]
                    if abs(target - heights[idx]) > epsilon {
                        out[idx] = target
                        changed += 1
                    }
                }
            }
        } else {
            // EROSION: lower material cells within the band toward the floor.
            // distToBoundary: chamfer distance from material → non-material/edge.
            var distToBoundary = [Double](repeating: inf, count: n)
            for i in 0..<n where !material[i] { distToBoundary[i] = 0 }
            chamferSweep(&distToBoundary, w: w, h: h, material: material, seedIsMaterial: false)

            for j in 0..<h {
                for i in 0..<w {
                    let idx = j * w + i
                    guard material[idx] else { continue }
                    let d = distToBoundary[idx]
                    guard d <= bandCells else { continue }
                    // d=1 (adjacent to boundary) → floor; d=band → keep height.
                    let t: Double
                    if bandCells <= 1.0 {
                        t = 0 // whole band eroded to the floor
                    } else {
                        t = max(0, (d - 1.0) / (bandCells - 1.0))
                    }
                    let target = floor + (heights[idx] - floor) * t
                    if abs(target - heights[idx]) > epsilon {
                        out[idx] = target
                        changed += 1
                    }
                }
            }
        }

        return OffsetResult(
            heightfield: HeightfieldData(
                width: w, height: h,
                cellSizeMm: heightfield.cellSizeMm,
                minX: heightfield.minX, minY: heightfield.minY,
                heights: out
            ),
            changedCellCount: changed,
            maxHeightAfter: out.max() ?? 0
        )
    }

    /// Two-pass chamfer distance transform. Seeded cells (distance 0) are
    /// either the material mask (`seedIsMaterial: true` → distance from each
    /// non-material cell to the nearest material cell) or its complement
    /// (`false` → distance from each material cell to the nearest boundary).
    private static func chamferSweep(_ dist: inout [Double], w: Int, h: Int,
                                     material: [Bool], seedIsMaterial: Bool) {
        func idx(_ i: Int, _ j: Int) -> Int { j * w + i }
        func inGrid(_ i: Int, _ j: Int) -> Bool { i >= 0 && i < w && j >= 0 && j < h }
        func seeded(_ i: Int, _ j: Int) -> Bool {
            guard inGrid(i, j) else { return false }
            return seedIsMaterial ? material[idx(i, j)] : !material[idx(i, j)]
        }

        // Forward pass (top-left → bottom-right).
        for j in 0..<h {
            for i in 0..<w {
                guard !seeded(i, j) else { continue }
                var best = dist[idx(i, j)]
                for (di, dj, wgt) in [(-1, -1, 1.414), (0, -1, 1.0), (-1, 0, 1.0), (1, -1, 1.414)] {
                    let ni = i + di, nj = j + dj
                    if inGrid(ni, nj), !seeded(ni, nj) {
                        best = min(best, dist[idx(ni, nj)] + wgt)
                    }
                }
                // Grid edge counts as a boundary at distance 1.0 for the
                // erosion direction.
                if !seedIsMaterial, (i == 0 || j == 0 || i == w - 1 || j == h - 1) {
                    best = min(best, 1.0)
                }
                // A seeded neighbor is distance 1.0 (or 1.414 diagonal) away.
                for (di, dj, wgt) in [(-1, 0, 1.0), (0, -1, 1.0), (-1, -1, 1.414)] {
                    let ni = i + di, nj = j + dj
                    if seeded(ni, nj) { best = min(best, wgt) }
                }
                dist[idx(i, j)] = best == inf ? 1.0 : best
            }
        }

        // Backward pass (bottom-right → top-left).
        for j in stride(from: h - 1, through: 0, by: -1) {
            for i in stride(from: w - 1, through: 0, by: -1) {
                guard !seeded(i, j) else { continue }
                var best = dist[idx(i, j)]
                for (di, dj, wgt) in [(1, 1, 1.414), (0, 1, 1.0), (1, 0, 1.0), (-1, 1, 1.414)] {
                    let ni = i + di, nj = j + dj
                    if inGrid(ni, nj), !seeded(ni, nj) {
                        best = min(best, dist[idx(ni, nj)] + wgt)
                    }
                }
                for (di, dj, wgt) in [(1, 0, 1.0), (0, 1, 1.0), (1, 1, 1.414)] {
                    let ni = i + di, nj = j + dj
                    if seeded(ni, nj) { best = min(best, wgt) }
                }
                dist[idx(i, j)] = best
            }
        }
    }

    /// Propagate the seeded (material) heights to every non-material cell —
    /// each cell receives the height of the nearest material cell (ties go to
    /// the forward/backward sweep order). Same two-pass structure as the
    /// chamfer sweep.
    private static func propagateHeights(_ heights: inout [Double], w: Int, h: Int,
                                         material: [Bool]) {
        func idx(_ i: Int, _ j: Int) -> Int { j * w + i }
        func inGrid(_ i: Int, _ j: Int) -> Bool { i >= 0 && i < w && j >= 0 && j < h }
        func seeded(_ i: Int, _ j: Int) -> Bool {
            guard inGrid(i, j) else { return false }
            return material[idx(i, j)]
        }

        // Forward pass (top-left → bottom-right).
        for j in 0..<h {
            for i in 0..<w {
                guard !seeded(i, j) else { continue }
                var best = heights[idx(i, j)]
                for (di, dj) in [(-1, -1), (0, -1), (-1, 0), (1, -1)] {
                    let ni = i + di, nj = j + dj
                    if inGrid(ni, nj) { best = max(best, heights[idx(ni, nj)]) }
                }
                heights[idx(i, j)] = best
            }
        }

        // Backward pass (bottom-right → top-left).
        for j in stride(from: h - 1, through: 0, by: -1) {
            for i in stride(from: w - 1, through: 0, by: -1) {
                guard !seeded(i, j) else { continue }
                var best = heights[idx(i, j)]
                for (di, dj) in [(1, 1), (0, 1), (1, 0), (-1, 1)] {
                    let ni = i + di, nj = j + dj
                    if inGrid(ni, nj) { best = max(best, heights[idx(ni, nj)]) }
                }
                heights[idx(i, j)] = best
            }
        }
    }
}

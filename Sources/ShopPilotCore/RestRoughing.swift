import Foundation

// MARK: - Rest machining planner (SPK-1305)

/// Rest machining: after a rough pass with a big tool, leftover material
/// (pockets the big tool couldn't reach, scallops, corner remnants) is
/// cleared by a smaller tool. This planner works on a REMAINING-DEPTH GRID —
/// the map of how much material is still left above the final surface at
/// each cell after the rough pass (a heightfield of leftovers).
///
/// It computes the z-level rest passes needed to clear everything above
/// `minRemaining` (the tolerance — material thinner than this is left for
/// the finish pass). Pure + testable; the session/UI wire the plan into a
/// pocket-style clearing toolpath.
public struct RestPass: Equatable, Sendable {
    /// Z depth of this rest pass (mm, measured from the stock top, negative
    /// going down — e.g. -2, -4, …). Cells are cleared layer by layer.
    public let depth: Double
    /// The grid cells (flat indices) that still have material at this layer.
    public let cellIndices: [Int]

    public init(depth: Double, cellIndices: [Int]) {
        self.depth = depth
        self.cellIndices = cellIndices
    }
}

public enum RestRoughing {

    /// Plan rest passes over a remaining-depth grid.
    /// - Parameters:
    ///   - remainingDepthGrid: per-cell remaining material above the final
    ///     surface, in mm (0 = clean, >0 = leftover to clear). Row-major.
    ///   - gridWidth: cells per row (validates the grid shape).
    ///   - stepDown: z per pass (mm). Clamped to [0.1, 50].
    ///   - minRemaining: tolerance — cells with material <= this are treated
    ///     as clean (left for the finish pass). Clamped to [0, 10].
    /// - Returns: rest passes shallow→deep. A cell with material `m` appears
    ///   in `ceil(m / stepDown)` passes (it is cleared in layers). Empty
    ///   when the grid is empty or nothing remains.
    public static func planRestPasses(
        remainingDepthGrid: [Double],
        gridWidth: Int,
        stepDown: Double = 2.0,
        minRemaining: Double = 0.3
    ) -> [RestPass] {
        guard !remainingDepthGrid.isEmpty, gridWidth > 0,
              remainingDepthGrid.count.isMultiple(of: gridWidth) else {
            return []
        }
        let step = min(50, max(0.1, stepDown))
        let tolerance = min(10, max(0, minRemaining))

        // Material to clear per cell (mm above tolerance).
        let material = remainingDepthGrid.map { max(0, $0 - tolerance) }
        let maxMaterial = material.max() ?? 0
        guard maxMaterial > 1e-9 else { return [] }

        let passCount = Int(ceil(maxMaterial / step))
        var passes: [RestPass] = []
        for k in 1...passCount {
            let depth = -Double(k) * step
            // A cell participates in pass k while it still has material at
            // this layer (its material exceeds (k-1)*step).
            let cells = material.enumerated()
                .filter { $0.element > Double(k - 1) * step + 1e-9 }
                .map(\.offset)
            passes.append(RestPass(depth: depth, cellIndices: cells))
        }
        return passes
    }

    /// Total pass count for a cell with `material` mm remaining (how many
    /// rest layers it needs). Used by the verify and the UI summary.
    public static func passCount(material: Double, stepDown: Double) -> Int {
        guard material > 1e-9 else { return 0 }
        return Int(ceil(max(0.1, min(50, stepDown)) > 0
                         ? material / max(0.1, min(50, stepDown)) : 0))
    }

    /// Total material cleared across all passes (mm·cells — the work volume
    /// proxy shown in the UI). Sums each cell's remaining material.
    public static func totalRemaining(_ grid: [Double], minRemaining: Double = 0.3) -> Double {
        grid.reduce(0) { $0 + max(0, $1 - minRemaining) }
    }
}

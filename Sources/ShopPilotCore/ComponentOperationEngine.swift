import Foundation

// MARK: - Component operations engine (SPK-0712: smooth / emboss / bake / split)

/// REAL engine behind the legacy `ModelOperations` stub (params + result
/// types only — this is the math). Applies component-level 3D operations to
/// heightfields:
///   - smooth: Laplacian relaxation over the grid (iterations + factor),
///     volume-preserving option re-normalizes so the mean height is kept.
///   - emboss: raise (Add) or recess (Subtract) a rounded stamp centered on
///     the grid — the classic "emboss a shape into a component" effect
///     without needing a text/mask rasterizer (text embossing is Phase H).
///   - bake: fold the visible component stack into ONE relief via the
///     existing compositor, then clear the stack — the document's active
///     relief becomes the composited surface (the reference "Bake visible").
///   - split: cut the relief at a horizontal plane height; returns the part
///     ABOVE the plane re-based to 0 (the below part is discarded), the
///     reference "split at height" behavior for making two-sided work.
public enum ComponentOperationEngine {

    // MARK: - Smooth

    /// Laplacian smooth: each cell moves toward the mean of its 4-neighbours
    /// by `factor` per iteration. Grid geometry is preserved.
    public static func smooth(
        _ hf: HeightfieldData,
        params: SmoothParams
    ) -> HeightfieldData {
        var heights = hf.heights
        let w = hf.width
        let h = hf.height
        for _ in 0..<max(1, params.iterations) {
            var next = heights
            for j in 0..<h {
                for i in 0..<w {
                    var sum = 0.0
                    var count = 0
                    if i > 0 { sum += heights[j * w + (i - 1)]; count += 1 }
                    if i < w - 1 { sum += heights[j * w + (i + 1)]; count += 1 }
                    if j > 0 { sum += heights[(j - 1) * w + i]; count += 1 }
                    if j < h - 1 { sum += heights[(j + 1) * w + i]; count += 1 }
                    guard count > 0 else { continue }
                    let mean = sum / Double(count)
                    next[j * w + i] = heights[j * w + i] + (mean - heights[j * w + i]) * params.smoothingFactor
                }
            }
            heights = next
        }
        if params.preserveVolume {
            let originalMean = hf.heights.reduce(0, +) / Double(max(1, hf.heights.count))
            let newMean = heights.reduce(0, +) / Double(max(1, heights.count))
            let shift = originalMean - newMean
            heights = heights.map { max(0, $0 + shift) }
        }
        return HeightfieldData(
            width: hf.width, height: hf.height,
            cellSizeMm: hf.cellSizeMm, minX: hf.minX, minY: hf.minY,
            heights: heights
        )
    }

    // MARK: - Emboss

    /// Emboss a rounded stamp into the relief: raised adds a dome (peak =
    /// `depth` at the center), recessed subtracts it (clamped ≥ 0). The stamp
    /// spans the full grid footprint so any component can carry it; mask-based
    /// text embossing stays Phase H.
    public static func emboss(
        _ hf: HeightfieldData,
        params: EmbossParams
    ) -> HeightfieldData {
        let w = hf.width
        let h = hf.height
        let cx = (Double(w) - 1) / 2.0
        let cy = (Double(h) - 1) / 2.0
        let maxR = hypot(cx, cy)
        var heights = hf.heights
        for j in 0..<h {
            for i in 0..<w {
                let r = hypot(Double(i) - cx, Double(j) - cy) / max(maxR, 1e-9)
                let stamp = params.depth * (1.0 - min(1.0, r))
                let idx = j * w + i
                switch params.embossType {
                case .raised:
                    heights[idx] = hf.heights[idx] + stamp
                case .recessed:
                    heights[idx] = max(0, hf.heights[idx] - stamp)
                case .stroke, .letterpress:
                    // Both behave like recessed for a single-pass stamp.
                    heights[idx] = max(0, hf.heights[idx] - stamp)
                }
            }
        }
        return HeightfieldData(
            width: hf.width, height: hf.height,
            cellSizeMm: hf.cellSizeMm, minX: hf.minX, minY: hf.minY,
            heights: heights
        )
    }

    // MARK: - Bake

    /// Bake the visible component stack into the active relief. Returns the
    /// composited grid (nil when nothing visible), or nil when the stack is
    /// empty. The caller owns clearing the stack.
    public static func bake(_ components: [ReliefComponent]) -> HeightfieldData? {
        ComponentCompositor.composite(components)
    }

    // MARK: - Split

    /// Split at a horizontal plane: returns the part ABOVE `planeHeight`
    /// re-based so its lowest point sits at 0 (cells below the plane become
    /// 0). The reference "split" for making two-sided parts; the below-part
    /// is discarded in this lean slice.
    public static func split(
        _ hf: HeightfieldData,
        planeHeight: Double
    ) -> HeightfieldData {
        let above = hf.heights.map { max(0, $0 - planeHeight) }
        let minAbove = above.min() ?? 0
        let rebased = above.map { $0 - minAbove }
        return HeightfieldData(
            width: hf.width, height: hf.height,
            cellSizeMm: hf.cellSizeMm, minX: hf.minX, minY: hf.minY,
            heights: rebased
        )
    }
}

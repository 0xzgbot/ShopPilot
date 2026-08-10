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

    // MARK: - Shift

    /// Shift the heightfield grid by integer cell offsets. Cells that shift
    /// outside the grid are filled with 0 (black = floor). The grid geometry
    /// is preserved.
    public static func shiftHeightfield(
        _ hf: HeightfieldData,
        shiftX: Int,
        shiftY: Int
    ) -> HeightfieldData? {
        guard shiftX != 0 || shiftY != 0 else { return hf }
        let w = hf.width, h = hf.height
        var heights = [Double](repeating: 0, count: w * h)
        for j in 0..<h {
            for i in 0..<w {
                let srcI = i - shiftX
                let srcJ = j - shiftY
                if srcI >= 0 && srcI < w && srcJ >= 0 && srcJ < h {
                    heights[j * w + i] = hf.heights[srcJ * w + srcI]
                }
            }
        }
        return HeightfieldData(
            width: w, height: h,
            cellSizeMm: hf.cellSizeMm, minX: hf.minX, minY: hf.minY,
            heights: heights
        )
    }

    // MARK: - Scale

    /// Scale the heightfield grid by a uniform factor using nearest-neighbor.
    /// Returns nil when the factor is ≤ 0 or the resulting grid would exceed
    /// 2048 cells per side (a drag-scale handle feeding a huge factor must not
    /// allocate e.g. 10^10 cells — 80GB OOM).
    public static func scaleHeightfield(
        _ hf: HeightfieldData,
        scaleFactor: Double
    ) -> HeightfieldData? {
        guard scaleFactor > 0 else { return nil }
        let w = hf.width, h = hf.height
        let newW = max(1, Int(Double(w) * scaleFactor))
        let newH = max(1, Int(Double(h) * scaleFactor))
        guard newW <= 2048, newH <= 2048 else { return nil }
        var heights = [Double](repeating: 0, count: newW * newH)
        for j in 0..<newH {
            for i in 0..<newW {
                let srcI = Int(Double(i) / max(0.001, scaleFactor))
                let srcJ = Int(Double(j) / max(0.001, scaleFactor))
                let si = min(srcI, w - 1)
                let sj = min(srcJ, h - 1)
                heights[j * newW + i] = hf.heights[sj * w + si]
            }
        }
        return HeightfieldData(
            width: newW, height: newH,
            cellSizeMm: hf.cellSizeMm / scaleFactor,
            minX: hf.minX, minY: hf.minY,
            heights: heights
        )
    }

    // MARK: - Rotate

    /// Rotate the heightfield grid by a multiple of 90 degrees (CW).
    /// Returns nil when degrees is not a multiple of 90.
    ///
    /// 90° rotation SWAPS the grid dimensions (W×H → H×W); the original
    /// implementation kept w×h fixed and read `src[(w-1-i)*w + j]`, which is
    /// only valid for square grids — for h > w the index exceeds `w*h` and the
    /// array read is out of bounds (crash). Each turn now maps
    /// `dest[j'][i'] = src[(h-1-i')*w + j']` with dims swapped after the turn.
    public static func rotateHeightfield(
        _ hf: HeightfieldData,
        degrees: Int
    ) -> HeightfieldData? {
        let norm = ((degrees % 360) + 360) % 360
        guard norm % 90 == 0 else { return nil }
        let turns = norm / 90
        var w = hf.width
        var h = hf.height
        var src = hf.heights
        for _ in 0..<turns {
            // 90° CW: new grid is h×w. dest row j' ∈ [0, w), dest col i' ∈ [0, h).
            var rotated = [Double](repeating: 0, count: w * h)
            for jp in 0..<w {
                for ip in 0..<h {
                    rotated[jp * h + ip] = src[(h - 1 - ip) * w + jp]
                }
            }
            src = rotated
            let newW = h
            let newH = w
            w = newW
            h = newH
        }
        return HeightfieldData(
            width: w, height: h,
            cellSizeMm: hf.cellSizeMm, minX: hf.minX, minY: hf.minY,
            heights: src
        )
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

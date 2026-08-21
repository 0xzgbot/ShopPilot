import Foundation

// MARK: - Image-to-Relief Parameters

/// SPK-1900e — tunables for converting a grayscale luminance image into a
/// 2.5D relief heightfield.
public struct ImageToReliefParams: Codable, Sendable {
    /// Stretch the histogram to the full 0..1 range using robust (2nd/98th
    /// percentile) floors so a low-contrast photo still carves full depth.
    public var autoLevels: Bool
    /// Gaussian smoothing sigma in grid cells (0 disables smoothing).
    public var gaussianSigmaCells: Double
    /// Unsharp-mask strength, -1..1. Positive sharpens (more local contrast),
    /// negative softens further.
    public var detailBoost: Double
    /// Peak relief height in mm.
    public var maxHeightMm: Double
    /// Longest side of the relief in mm (aspect preserved).
    public var maxWidthMm: Double
    /// Grid cells along the longest side.
    public var gridResolution: Int
    /// Flip bright↔dark (carve recesses instead of peaks).
    public var invert: Bool

    public init(
        autoLevels: Bool = true,
        gaussianSigmaCells: Double = 1.5,
        detailBoost: Double = 0.0,
        maxHeightMm: Double = 5.0,
        maxWidthMm: Double = 100.0,
        gridResolution: Int = 200,
        invert: Bool = false
    ) {
        self.autoLevels = autoLevels
        self.gaussianSigmaCells = gaussianSigmaCells
        self.detailBoost = detailBoost
        self.maxHeightMm = maxHeightMm
        self.maxWidthMm = maxWidthMm
        self.gridResolution = gridResolution
        self.invert = invert
    }
}

// MARK: - Engine

/// SPK-1900e — converts an image's luminance field into a carveable relief:
/// sanitize → auto-levels → gaussian blur → detail boost → invert → scale to
/// mm → resample onto a uniform-cell grid whose longest side is `maxWidthMm`.
/// Pure Foundation, fully deterministic.
public enum ImageToReliefEngine {

    public static func generateHeightfield(
        luminance: [[Double]],
        params: ImageToReliefParams
    ) -> HeightfieldData {
        let rowCount = luminance.count
        let colCount = luminance.first?.count ?? 0
        guard rowCount > 0, colCount > 0 else {
            let cell = (params.maxWidthMm.isFinite && params.maxWidthMm > 0)
                ? params.maxWidthMm : 1.0
            return HeightfieldData(
                width: 1, height: 1, cellSizeMm: cell, minX: 0, minY: 0, heights: [0]
            )
        }

        // (0) Sanitize: non-finite → 0, out-of-range clamped to 0..1.
        var values = [Double](repeating: 0, count: rowCount * colCount)
        for r in 0..<rowCount {
            let row = luminance[r]
            let base = r * colCount
            for c in 0..<colCount {
                var v = c < row.count ? row[c] : 0
                if !v.isFinite { v = 0 }
                values[base + c] = min(1.0, max(0.0, v))
            }
        }

        // (a) Auto levels: robust 2nd/98th percentile stretch.
        if params.autoLevels {
            values = Self.autoLevel(values)
        }

        // (b) Separable gaussian blur, edge-clamped.
        let sigma = (params.gaussianSigmaCells.isFinite && params.gaussianSigmaCells > 0)
            ? params.gaussianSigmaCells : 0
        let blurred = sigma > 0
            ? Self.gaussianBlur(values, cols: colCount, rows: rowCount, sigma: sigma)
            : values

        // (c) Detail boost (unsharp mask) + (d) invert + (e) scale to mm.
        var boost = params.detailBoost
        if !boost.isFinite { boost = 0 }
        boost = min(1.0, max(-1.0, boost))
        var maxHeight = params.maxHeightMm
        if !maxHeight.isFinite || maxHeight < 0 { maxHeight = 0 }

        var processed = [Double](repeating: 0, count: values.count)
        for i in 0..<values.count {
            var v = blurred[i]
            if boost != 0 {
                v = blurred[i] + boost * (values[i] - blurred[i])
            }
            v = min(1.0, max(0.0, v))
            if params.invert { v = 1.0 - v }
            processed[i] = max(0, v * maxHeight)
        }

        // Physical sizing: longest side = maxWidthMm, aspect preserved,
        // uniform square cells. Longest axis gets `gridResolution` cells.
        let maxWidth = (params.maxWidthMm.isFinite && params.maxWidthMm > 0)
            ? params.maxWidthMm : 100.0
        var resolution = params.gridResolution
        if resolution < 2 { resolution = 2 }
        let aspect = Double(colCount) / Double(rowCount)
        let gridW: Int, gridH: Int
        if aspect >= 1 {
            gridW = resolution
            gridH = max(1, Int((Double(resolution) / aspect).rounded()))
        } else {
            gridH = resolution
            gridW = max(1, Int((Double(resolution) * aspect).rounded()))
        }
        let cellSizeMm = maxWidth / Double(resolution)

        // Bilinear resample of the processed pixels onto the target grid
        // (pixel centers treated as sample points, edge-clamped).
        var heights = [Double](repeating: 0, count: gridW * gridH)
        let srcMaxX = Double(colCount - 1)
        let srcMaxY = Double(rowCount - 1)
        for gy in 0..<gridH {
            let fy = gridH > 1
                ? Double(gy) / Double(gridH - 1) * srcMaxY : srcMaxY * 0.5
            let y0 = min(rowCount - 1, Int(fy.rounded(.down)))
            let y1 = min(rowCount - 1, y0 + 1)
            let ty = fy - Double(y0)
            for gx in 0..<gridW {
                let fx = gridW > 1
                    ? Double(gx) / Double(gridW - 1) * srcMaxX : srcMaxX * 0.5
                let x0 = min(colCount - 1, Int(fx.rounded(.down)))
                let x1 = min(colCount - 1, x0 + 1)
                let tx = fx - Double(x0)
                let h00 = processed[y0 * colCount + x0]
                let h10 = processed[y0 * colCount + x1]
                let h01 = processed[y1 * colCount + x0]
                let h11 = processed[y1 * colCount + x1]
                let top = h00 + (h10 - h00) * tx
                let bottom = h01 + (h11 - h01) * tx
                heights[gy * gridW + gx] = top + (bottom - top) * ty
            }
        }

        return HeightfieldData(
            width: gridW, height: gridH,
            cellSizeMm: cellSizeMm, minX: 0, minY: 0,
            heights: heights
        )
    }

    // MARK: - Pipeline stages

    /// Stretch to full 0..1 using the 2nd/98th percentile as floor/ceiling;
    /// values outside are clamped. Degenerate (constant) input maps to 0.5.
    static func autoLevel(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return values }
        let sorted = values.sorted()
        let n = sorted.count
        let loIdx = min(n - 1, max(0, Int(0.02 * Double(n - 1))))
        let hiIdx = min(n - 1, max(0, Int(0.98 * Double(n - 1))))
        let lo = sorted[loIdx]
        let hi = sorted[hiIdx]
        let range = hi - lo
        guard range > 1e-12 else {
            return [Double](repeating: 0.5, count: n)
        }
        return values.map { min(1.0, max(0.0, ($0 - lo) / range)) }
    }

    /// Separable gaussian blur over a row-major grid with edge-clamped
    /// sampling. Kernel radius = ceil(3σ); weights normalized.
    static func gaussianBlur(_ values: [Double], cols: Int, rows: Int, sigma: Double) -> [Double] {
        guard cols > 0, rows > 0, sigma > 0, values.count == cols * rows else {
            return values
        }
        let radius = max(1, Int((3.0 * sigma).rounded(.up)))
        var kernel = [Double](repeating: 0, count: 2 * radius + 1)
        var sum = 0.0
        let denom = 2.0 * sigma * sigma
        for i in -radius...radius {
            let w = exp(-Double(i * i) / denom)
            kernel[i + radius] = w
            sum += w
        }
        for i in kernel.indices { kernel[i] /= sum }

        // Horizontal pass.
        var tmp = [Double](repeating: 0, count: values.count)
        for r in 0..<rows {
            let base = r * cols
            for c in 0..<cols {
                var acc = 0.0
                for k in -radius...radius {
                    let sc = min(cols - 1, max(0, c + k))
                    acc += values[base + sc] * kernel[k + radius]
                }
                tmp[base + c] = acc
            }
        }
        // Vertical pass.
        var out = [Double](repeating: 0, count: values.count)
        for r in 0..<rows {
            for c in 0..<cols {
                var acc = 0.0
                for k in -radius...radius {
                    let sr = min(rows - 1, max(0, r + k))
                    acc += tmp[sr * cols + c] * kernel[k + radius]
                }
                out[r * cols + c] = acc
            }
        }
        return out
    }
}

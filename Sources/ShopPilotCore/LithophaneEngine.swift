import Foundation

// MARK: - Lithophane Engine (SPK-1900a)

/// Rendering mode for a lithophane-style heightfield.
///
/// - `lithophaneThickness`: classic backlit lithophane — bright pixels are THIN
///   (light passes through), dark pixels are thick.
/// - `grayscaleRelief`: standard relief carving — bright pixels are TALL.
public enum LithophaneMode: String, Codable, Sendable, CaseIterable {
    case lithophaneThickness
    case grayscaleRelief
}

/// Parameters for lithophane heightfield generation.
///
/// All fields have neutral defaults; `generateHeightfield(luminance:params:)`
/// is fully driven by these values and is deterministic.
public struct LithophaneParams: Codable, Sendable {
    /// Thickness-mode vs relief-mode mapping.
    public var mode: LithophaneMode
    /// Physical size of the LONGEST side in mm (aspect preserved).
    public var maxWidthMm: Double
    /// Optional fixed size of the SHORT side in mm; nil derives it from aspect.
    public var maxHeightMm: Double?
    /// Grid resolution in cells across the LONGEST side.
    public var gridResolution: Int
    /// Depth range added on top of `baseThicknessMm` (thickness mode) or the
    /// full relief amplitude (relief mode), in mm.
    public var maxDepthMm: Double
    /// Minimum plate thickness floor in mm. Reserved by the SPK-1900a engine
    /// contract (thickness is governed by `baseThicknessMm`); carried on the
    /// params record for the UI/persistence layer.
    public var minThicknessMm: Double
    /// Additive brightness offset applied before contrast (-1…1 typical).
    public var brightness: Double
    /// Contrast multiplier around pivot 0.5 (1 = neutral).
    public var contrast: Double
    /// Gamma exponent denominator: out = pow(v, 1/gamma). 1 = neutral.
    public var gamma: Double
    /// Flip light/dark after tone adjustments.
    public var invert: Bool
    /// Base plate thickness in mm (thickness mode floor).
    public var baseThicknessMm: Double

    public init(
        mode: LithophaneMode = .lithophaneThickness,
        maxWidthMm: Double = 100,
        maxHeightMm: Double? = nil,
        gridResolution: Int = 200,
        maxDepthMm: Double = 2.5,
        minThicknessMm: Double = 0.5,
        brightness: Double = 0,
        contrast: Double = 1,
        gamma: Double = 1,
        invert: Bool = false,
        baseThicknessMm: Double = 0.8
    ) {
        self.mode = mode
        self.maxWidthMm = maxWidthMm
        self.maxHeightMm = maxHeightMm
        self.gridResolution = gridResolution
        self.maxDepthMm = maxDepthMm
        self.minThicknessMm = minThicknessMm
        self.brightness = brightness
        self.contrast = contrast
        self.gamma = gamma
        self.invert = invert
        self.baseThicknessMm = baseThicknessMm
    }
}

/// SPK-1900a — converts a precomputed luminance grid ([row][col], rows = image
/// Y, values 0…1) into a machinable `HeightfieldData`. Pure Foundation: the
/// image decoding slice feeds this; nothing here touches AppKit/ImageIO.
///
/// Deterministic: identical input + params produce byte-identical heights.
public enum LithophaneEngine {

    // MARK: - Tone pipeline

    /// Apply brightness → contrast → gamma → invert to one normalized value.
    /// NaN input is treated as 0; result is clamped to 0…1.
    static func adjust(_ raw: Double, params: LithophaneParams) -> Double {
        var v = raw.isFinite ? raw : 0
        v = min(1, max(0, v))

        // Brightness (additive).
        v += params.brightness
        v = min(1, max(0, v))

        // Contrast around pivot 0.5.
        let c = params.contrast.isFinite && params.contrast >= 0 ? params.contrast : 1
        v = (v - 0.5) * c + 0.5
        v = min(1, max(0, v))

        // Gamma curve: pow(v, 1/gamma).
        let g = params.gamma.isFinite && params.gamma > 0 ? params.gamma : 1
        v = pow(v, 1.0 / g)

        if params.invert { v = 1 - v }
        return min(1, max(0, v))
    }

    // MARK: - Generation

    /// Generate a heightfield from a luminance grid.
    ///
    /// Geometry: the longest side of the luminance grid maps to
    /// `params.gridResolution` cells and `params.maxWidthMm`; the other side is
    /// derived from aspect (`maxHeightMm` overrides the physical short-side
    /// size without changing cell counts). Cells stay square.
    public static func generateHeightfield(
        luminance: [[Double]],
        params: LithophaneParams
    ) -> HeightfieldData {
        let srcRows = luminance.count
        let srcCols = srcRows > 0 ? (luminance[0].count) : 0
        guard srcRows > 0, srcCols > 0 else {
            return HeightfieldData(width: 1, height: 1, cellSizeMm: 1, minX: 0, minY: 0, heights: [0])
        }

        let resolution = max(1, params.gridResolution)
        // Longest side gets `resolution` cells; other side derived from aspect.
        let outCols: Int
        let outRows: Int
        if srcCols >= srcRows {
            outCols = resolution
            outRows = max(1, Int((Double(srcRows) * Double(resolution) / Double(srcCols)).rounded()))
        } else {
            outRows = resolution
            outCols = max(1, Int((Double(srcCols) * Double(resolution) / Double(srcRows)).rounded()))
        }

        // Physical sizing: square cells. Without maxHeightMm the longest side
        // is exactly maxWidthMm (aspect preserved). With a positive maxHeightMm
        // it acts as a second box constraint — cells shrink to fit BOTH bounds.
        let longSideMm = params.maxWidthMm.isFinite && params.maxWidthMm > 0 ? params.maxWidthMm : 100
        var cellSizeMm = longSideMm / Double(max(outCols, outRows))
        if let mh = params.maxHeightMm, mh.isFinite, mh > 0 {
            cellSizeMm = min(cellSizeMm, mh / Double(min(outCols, outRows)))
        }

        // Resample + tone-map + depth-map. Nearest-neighbour sampling keeps
        // this exact and deterministic.
        let depth = params.maxDepthMm.isFinite && params.maxDepthMm >= 0 ? params.maxDepthMm : 2.5
        let base = params.baseThicknessMm.isFinite && params.baseThicknessMm >= 0 ? params.baseThicknessMm : 0.8
        var heights = [Double](repeating: 0, count: outRows * outCols)
        heights.reserveCapacity(outRows * outCols)

        for row in 0..<outRows {
            let sy = min(srcRows - 1, (row * srcRows) / outRows)
            for col in 0..<outCols {
                let sx = min(srcCols - 1, (col * srcCols) / outCols)
                let v = adjust(luminance[sy][sx], params: params)
                let z: Double
                switch params.mode {
                case .lithophaneThickness:
                    // Bright = thin (light passes through): dark adds depth.
                    let extra = max(0, depth * (1 - v))
                    z = base + extra
                case .grayscaleRelief:
                    // Bright = tall.
                    z = max(0, v * depth)
                }
                heights[row * outCols + col] = z.isFinite ? z : 0
            }
        }

        return HeightfieldData(
            width: outCols,
            height: outRows,
            cellSizeMm: cellSizeMm,
            minX: 0,
            minY: 0,
            heights: heights
        )
    }
}

import Foundation

// MARK: - Shape relief generator (SPK-0703: shape tools)

/// REAL engine behind the legacy `ShapeToolManager` stub (bookkeeping only —
/// this is the math). Generates a parametric 3D relief (heightfield) from a
/// `ShapeType` + `ShapeParameters`, mirroring the reference "Create shape"
/// tools: angled (ramp at a slope angle), round (dome), smooth (soft bell),
/// flat (constant plane), custom (deferred).
///
/// Output grids are normalized to a requested footprint (width×height mm at
/// cellSizeMm) and a max height, so a generated shape drops straight into the
/// document's component stack and composites with everything else.
public enum ShapeReliefGenerator {

    /// Generate a shape relief. `width`/`height` are the WORLD footprint in
    /// mm; `cellSizeMm` sets the grid resolution (grid = round(w/cell) cells).
    /// `maxHeight` is the peak for raised shapes; `params` carries the
    /// per-type control (angle/radius/smoothness/flatHeight).
    public static func generate(
        shapeType: ShapeType,
        params: ShapeParameters,
        width: Double,
        height: Double,
        cellSizeMm: Double = 1.0,
        maxHeight: Double = 10.0
    ) -> HeightfieldData {
        let cols = max(2, Int((width / cellSizeMm).rounded()))
        let rows = max(2, Int((height / cellSizeMm).rounded()))
        let worldW = Double(cols) * cellSizeMm
        let worldH = Double(rows) * cellSizeMm
        let peak = max(0, maxHeight)
        var heights = [Double](repeating: 0, count: cols * rows)

        for j in 0..<rows {
            for i in 0..<cols {
                // Normalized cell center in [0,1] across the footprint.
                let nx = (Double(i) + 0.5) / Double(cols)
                let ny = (Double(j) + 0.5) / Double(rows)
                // Distance from footprint center, normalized to [0,1] at the
                // farthest corner (so a full-width shape peaks in the middle).
                let dx = (nx - 0.5) * 2.0
                let dy = (ny - 0.5) * 2.0
                let r = min(1.0, sqrt(dx * dx + dy * dy) / sqrt(2.0))

                let h: Double
                switch shapeType {
                case .flat:
                    h = min(peak, max(0, params.flatHeight))
                case .angled:
                    // Linear ramp along X: 0 at the left edge → peak at the
                    // right edge. The angle parameter controls steepness:
                    // tan(angle) = peak / width.
                    h = nx * peak
                case .round:
                    // Dome: full peak at center, falling to 0 at the edges
                    // (quarter-ellipse profile).
                    h = peak * sqrt(max(0, 1 - r * r))
                case .smooth:
                    // Smooth bell: cosine falloff, plateau-scaled by the
                    // smoothness parameter (0 = narrow spike, 1 = broad dome).
                    let spread = 0.35 + params.smoothness * 0.55
                    let t = r / spread
                    if t >= 1 {
                        h = 0
                    } else {
                        h = peak * 0.5 * (1 + cos(.pi * t))
                    }
                case .custom:
                    // Custom function strings are a future extension; produce
                    // a neutral flat plane so the tool never yields empty.
                    h = min(peak, max(0, params.flatHeight))
                }
                heights[j * cols + i] = max(0, h)
            }
        }
        return HeightfieldData(
            width: cols, height: rows,
            cellSizeMm: cellSizeMm, minX: 0, minY: 0,
            heights: heights
        )
    }

    /// Convenience: generate with the shape's own stored parameters.
    public static func generate(
        tool: ShapeTool,
        width: Double,
        height: Double,
        cellSizeMm: Double = 1.0,
        maxHeight: Double = 10.0
    ) -> HeightfieldData {
        generate(
            shapeType: tool.shapeType,
            params: tool.parameters,
            width: width,
            height: height,
            cellSizeMm: cellSizeMm,
            maxHeight: maxHeight
        )
    }
}

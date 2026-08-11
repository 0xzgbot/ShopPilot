import Foundation
import ShopPilotCore

// MARK: - 3D Text Relief Engine (SPK-1319)

/// Rasterizes text glyph outlines into a 2.5D relief (heightfield) so the app
/// can carve raised / engraved letters — the "3D text" feature.
///
/// Pipeline: glyph outline polygons → per-glyph boolean rasters (point-in-
/// polygon, even-odd fill) → composite all rasters into one `HeightfieldData`
/// where letter interiors stand proud (full stock height) and the surrounding
/// surface is cut down by the carve depth.
public enum ReliefText3D {

    /// Rasterize ONE glyph's outline into a boolean grid.
    ///
    /// - Parameters:
    ///   - outlinePoints: The glyph outline as a polygon. May be passed closed
    ///     (first point repeated) or open — an implied closing edge back to the
    ///     first point is added when missing.
    ///   - resolutionMm: Cell size in mm (grid spacing).
    ///   - bounds: World-space rectangle the grid covers.
    /// - Returns: `[row][col]` grid; `true` = inside the letter (raised),
    ///   `false` = background. Even-odd fill rule — convex, concave, and
    ///   self-intersecting outlines all produce a valid (never-crash) result.
    public static func rasterizeGlyph(
        outlinePoints: [VectorPoint],
        resolutionMm: Double,
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)
    ) -> [[Bool]] {
        // Degenerate input → a single false cell; never crash.
        guard resolutionMm > 1e-9,
              bounds.maxX > bounds.minX,
              bounds.maxY > bounds.minY else {
            return [[false]]
        }
        let cols = max(1, Int(ceil((bounds.maxX - bounds.minX) / resolutionMm)))
        let rows = max(1, Int(ceil((bounds.maxY - bounds.minY) / resolutionMm)))

        // Fewer than 3 points can't enclose area → all-false grid.
        guard outlinePoints.count >= 3 else {
            return [[Bool]](repeating: [Bool](repeating: false, count: cols), count: rows)
        }

        // Implied-close the polygon (a repeated closing point is harmless).
        var pts = outlinePoints
        if pts.first != pts.last {
            pts.append(pts[0])
        }

        var grid = [[Bool]](repeating: [Bool](repeating: false, count: cols), count: rows)
        for row in 0..<rows {
            let cy = bounds.minY + (Double(row) + 0.5) * resolutionMm
            for col in 0..<cols {
                let cx = bounds.minX + (Double(col) + 0.5) * resolutionMm
                grid[row][col] = isInsideEvenOdd(px: cx, py: cy, polygon: pts)
            }
        }
        return grid
    }

    /// Composite glyph rasters into ONE relief heightfield.
    ///
    /// Convention (letters stand proud): cells inside any glyph keep the full
    /// `stockThicknessMm`; background cells are cut down to
    /// `stockThicknessMm - carveDepthMm`.
    ///
    /// Each glyph raster is a FLAT row-major `[Bool]` (matching the
    /// `HeightfieldData.heights` convention). All rasters must have the same
    /// cell count — the grid is square (`side = √cellCount` when `cellCount`
    /// is a perfect square; otherwise a single row is used). If any raster's
    /// cell count differs, an empty `HeightfieldData` (heights == []) is
    /// returned — never a crash.
    public static func buildHeightfield(
        glyphRasters: [[Bool]],
        cellSizeMm: Double,
        stockThicknessMm: Double,
        carveDepthMm: Double,
        originX: Double,
        originY: Double
    ) -> HeightfieldData {
        func empty() -> HeightfieldData {
            HeightfieldData(
                width: 1, height: 1,
                cellSizeMm: cellSizeMm,
                minX: originX, minY: originY,
                heights: []
            )
        }

        guard cellSizeMm > 1e-9,
              let first = glyphRasters.first,
              !first.isEmpty else {
            return empty()
        }
        let cellCount = first.count

        // Validate: every raster must carry the same cell count.
        for raster in glyphRasters where raster.count != cellCount {
            return empty()
        }

        // Composite grid shape: square when possible, else a single row.
        let side = Int(sqrt(Double(cellCount)))
        let cols: Int
        let rows: Int
        if side * side == cellCount {
            cols = side
            rows = side
        } else {
            cols = cellCount
            rows = 1
        }

        let background = stockThicknessMm - carveDepthMm
        var heights = [Double](repeating: background, count: cellCount)
        for i in 0..<cellCount {
            var raised = false
            for raster in glyphRasters where raster[i] {
                raised = true
                break
            }
            if raised { heights[i] = stockThicknessMm }
        }
        return HeightfieldData(
            width: cols, height: rows,
            cellSizeMm: cellSizeMm,
            minX: originX, minY: originY,
            heights: heights
        )
    }

    /// Count letters and rasterizable glyphs in a text string.
    ///
    /// Spaces (whitespace) contribute no raster, so `totalGlyphs` counts only
    /// the non-whitespace characters — identical to `letterCount`.
    public static func lettersAndSpacing(_ text: String) -> (letterCount: Int, totalGlyphs: Int) {
        let letters = text.reduce(into: 0) { count, ch in
            if !ch.isWhitespace { count += 1 }
        }
        return (letters, letters)
    }

    // MARK: - Even-odd point-in-polygon

    /// Even-odd fill test: count crossings of a +X ray from (px, py) against
    /// the closed polygon. The half-open edge rule (`(a.y > py) != (b.y > py)`)
    /// keeps vertices lying exactly on the ray consistent and guarantees
    /// `b.y != a.y` whenever a crossing is evaluated (no division by zero).
    /// Self-intersecting polygons simply toggle per crossing — no crash.
    private static func isInsideEvenOdd(px: Double, py: Double, polygon: [VectorPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[j]
            if (a.y > py) != (b.y > py) {
                let xAtY = a.x + (py - a.y) * (b.x - a.x) / (b.y - a.y)
                if xAtY > px { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

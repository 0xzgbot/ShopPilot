import Foundation

// MARK: - Heightfield Visualizer (SPK-3D-UI)

/// Pure, testable 2D visualization helpers for a relief heightfield — the
/// Model stage renders these. Kept in Core (no SwiftUI/SceneKit) so the
/// ShopPilotVerify3DUI CLT can prove the mapping math without a GPU.
public struct HeightfieldVisualizer {

    /// 0…1 normalized height at a grid cell (peak → 1, floor → 0).
    /// Outside the grid → 0. Uses the cell-center sample convention.
    public static func normalizedHeight(
        _ hf: HeightfieldData,
        xCell: Int,
        yCell: Int
    ) -> Double {
        guard hf.maxHeight > 1e-9,
              xCell >= 0, xCell < hf.width,
              yCell >= 0, yCell < hf.height else { return 0 }
        return hf.heights[yCell * hf.width + xCell] / hf.maxHeight
    }

    /// Grayscale RGBA row-major pixels for the whole grid: 255 = peak,
    /// 0 = floor. `pixelSize` > 1 upscales with nearest-neighbor (no blur —
    /// keeps the CLT check exact). Row 0 = minY.
    public static func heightmapGrayscale(
        _ hf: HeightfieldData,
        pixelSize: Int = 1
    ) -> (pixels: [UInt8], widthPx: Int, heightPx: Int) {
        let w = max(1, hf.width * max(1, pixelSize))
        let h = max(1, hf.height * max(1, pixelSize))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for j in 0..<h {
            let yCell = j / max(1, pixelSize)
            for i in 0..<w {
                let xCell = i / max(1, pixelSize)
                let v = UInt8((normalizedHeight(hf, xCell: xCell, yCell: yCell) * 255).rounded())
                let idx = (j * w + i) * 4
                pixels[idx] = v       // R
                pixels[idx + 1] = v   // G
                pixels[idx + 2] = v   // B
                pixels[idx + 3] = 255 // A
            }
        }
        return (pixels, w, h)
    }

    /// Contour bands: for each of `levels` evenly spaced thresholds in
    /// [0, 1] (normalized), the count of grid cells above that threshold.
    /// Proves the relief has real topography and gives the Model stage a
    /// "contours: N" readout.
    public static func contourCounts(
        _ hf: HeightfieldData,
        levels: Int = 5
    ) -> [Int] {
        guard levels > 0 else { return [] }
        return (1...levels).map { level in
            let t = Double(level) / Double(levels)
            var count = 0
            for j in 0..<hf.height {
                for i in 0..<hf.width where normalizedHeight(hf, xCell: i, yCell: j) >= t {
                    count += 1
                }
            }
            return count
        }
    }
}

// MARK: - Heightfield Camera

/// Basic orbit-less 2.5D camera for the relief canvas: zoom + pan in world
/// coordinates. Pure math so the CLT can prove round-trips.
public struct HeightfieldCamera: Sendable {
    public var zoom: Double {   // 0.1…8.0, 1 = fit — self-clamping on set
        didSet { zoom = min(8.0, max(0.1, zoom)) }
    }
    public var panX: Double        // world-space offset
    public var panY: Double
    public let cellSizeMm: Double

    public init(zoom: Double = 1.0, panX: Double = 0, panY: Double = 0, cellSizeMm: Double = 1.0) {
        self.zoom = min(8.0, max(0.1, zoom))
        self.panX = panX
        self.panY = panY
        self.cellSizeMm = cellSizeMm
    }

    public mutating func zoom(by factor: Double) {
        zoom = min(8.0, max(0.1, zoom * factor))
    }

    /// Grid cell → view point (pixels). Grid minX/minY at zoom 1/pan 0 maps
    /// to (0,0); +x right, +y down (screen convention).
    public func cellToView(xCell: Int, yCell: Int) -> (x: Double, y: Double) {
        (
            (Double(xCell) * cellSizeMm + panX) * zoom,
            (Double(yCell) * cellSizeMm + panY) * zoom
        )
    }

    /// View point (pixels) → grid cell (nearest, clamped). Inverse of
    /// `cellToView` — the CLT proves the round-trip.
    public func viewToCell(x: Double, y: Double, width: Int, height: Int) -> (xCell: Int, yCell: Int) {
        let wx = x / zoom - panX
        let wy = y / zoom - panY
        let xCell = Int((wx / cellSizeMm).rounded())
        let yCell = Int((wy / cellSizeMm).rounded())
        return (
            max(0, min(width - 1, xCell)),
            max(0, min(height - 1, yCell))
        )
    }
}

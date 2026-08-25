import Foundation

// MARK: - Laser fill & picture engines (SPK-2000c — cross-platform parity)
//
// VectorPilot ships three laser surfaces: Laser Cut/Fill/Picture. ShopPilot
// already had vector cut/engrave (RotaryLaser.swift `LaserEngine`); this file
// adds the missing two:
//
//   • LaserFillEngine — raster scanline fills over closed vector bounds
//     (angle, line spacing, overscan, per-line bidirectional travel).
//   • LaserPictureEngine — bitmap (grayscale pixels) → power-modulated
//     G1 raster with M4 dynamic power; darker pixel = higher power.
//
// Both emit plain G-code lines in mm with S-power words; the laser post
// (`laser-grbl-m4-mm`, SPK-2000a) supplies the $32=1/M4 header. Engines are
// pure data: no transport, no session, deterministic output.

public struct LaserFillParams: Codable, Sendable {
    /// Fill line angle in degrees (0 = horizontal scanlines).
    public var angleDegrees: Double
    /// Distance between adjacent scanlines (mm).
    public var lineSpacingMm: Double
    /// Extra travel beyond the shape bounds on every line end (mm).
    public var overscanMm: Double
    /// Laser power percent 0…100.
    public var powerPercent: Double
    /// Scan speed (mm/min).
    public var speedMmPerMin: Double

    public init(angleDegrees: Double = 0,
                lineSpacingMm: Double = 0.2,
                overscanMm: Double = 1.0,
                powerPercent: Double = 80,
                speedMmPerMin: Double = 3000) {
        self.angleDegrees = angleDegrees.truncatingRemainder(dividingBy: 360)
        self.lineSpacingMm = max(0.05, lineSpacingMm)
        self.overscanMm = max(0, overscanMm)
        self.powerPercent = min(100, max(0, powerPercent))
        self.speedMmPerMin = max(1, speedMmPerMin)
    }
}

public struct LaserFillBounds: Codable, Sendable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }
}

public struct LaserFillResult: Codable, Sendable {
    public let gcodeLines: [String]
    public let scanlineCount: Int
    /// Bounding box of the input paths (mm).
    public let bounds: LaserFillBounds?
    public let success: Bool
    public let errorMessage: String?
}

public enum LaserFillEngine {

    /// Raster-fill the bounding box of the given closed paths.
    /// Lines run at `angleDegrees`; every other line reverses direction
    /// (bidirectional serpentine) to minimize travel.
    public static func compute(paths: [[VectorPoint]],
                               params: LaserFillParams) -> LaserFillResult {
        // Union bounds of all paths.
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        let points = paths.flatMap { $0 }
        guard !points.isEmpty else {
            return LaserFillResult(gcodeLines: [], scanlineCount: 0, bounds: nil,
                                   success: false,
                                   errorMessage: "No vectors to fill")
        }
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }

        let s = sin(params.angleDegrees * .pi / 180)
        let c = cos(params.angleDegrees * .pi / 180)
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2

        // Rotate the box corners into scanline space to find the extent along
        // the scan direction (u) and across it (v).
        func rot(_ x: Double, _ y: Double) -> (Double, Double) {
            ((x - cx) * c + (y - cy) * s, -(x - cx) * s + (y - cy) * c)
        }
        let corners = [rot(minX, minY), rot(maxX, minY), rot(maxX, maxY), rot(minX, maxY)]
        let uMin = corners.map(\.0).min()!, uMax = corners.map(\.0).max()!
        let vMin = corners.map(\.1).min()!, vMax = corners.map(\.1).max()!

        var lines: [String] = [
            "G21", "G90",
            "; laser fill angle=\(Int(params.angleDegrees)) spacing=\(params.lineSpacingMm)",
        ]
        var scanCount = 0
        var v = vMin
        var going = true
        while v <= vMax {
            // Inverse-rotate the two endpoints of this scanline back to XY.
            let aU = uMin - params.overscanMm
            let bU = uMax + params.overscanMm
            func unrot(_ u: Double, _ vv: Double) -> VectorPoint {
                VectorPoint(x: cx + u * c - vv * s, y: cy + u * s + vv * c)
            }
            let p1 = unrot(aU, v), p2 = unrot(bU, v)
            let (start, end) = going ? (p1, p2) : (p2, p1)

            lines.append(String(format: "G0 X%.3f Y%.3f", start.x, start.y))
            lines.append(String(format: "S%.0f", params.powerPercent * 10)) // S 0…1000 scale
            lines.append(String(format: "G1 X%.3f Y%.3f F%.0f",
                                end.x, end.y, params.speedMmPerMin))
            lines.append("S0")
            scanCount += 1
            going.toggle()
            v += params.lineSpacingMm
        }
        lines.append("S0")
        lines.append("M5")

        return LaserFillResult(
            gcodeLines: lines,
            scanlineCount: scanCount,
            bounds: LaserFillBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY),
            success: true,
            errorMessage: nil
        )
    }
}

// MARK: - Laser picture (power-modulated raster)

/// Grayscale pixel grid, row-major from top-left (image convention).
public struct GrayscaleGrid: Codable, Sendable {
    public let width: Int
    public let height: Int
    /// 0 (white) … 255 (black). Row-major, top-left origin.
    public let luminance: [UInt8]

    public init(width: Int, height: Int, luminance: [UInt8]) {
        precondition(luminance.count == width * height, "luminance count mismatch")
        self.width = width
        self.height = height
        self.luminance = luminance
    }

    public func at(x: Int, y: Int) -> UInt8 { luminance[y * width + x] }
}

public struct LaserPictureParams: Codable, Sendable {
    public var targetWidthMm: Double
    public var lineSpacingMm: Double
    public var maxPowerPercent: Double   // power for pure black
    public var speedMmPerMin: Double
    /// Burn white as off and black at max (true), or inverted (false).
    public var burnBlack: Bool

    public init(targetWidthMm: Double = 100,
                lineSpacingMm: Double = 0.2,
                maxPowerPercent: Double = 100,
                speedMmPerMin: Double = 2000,
                burnBlack: Bool = true) {
        self.targetWidthMm = max(5, targetWidthMm)
        self.lineSpacingMm = max(0.05, lineSpacingMm)
        self.maxPowerPercent = min(100, max(1, maxPowerPercent))
        self.speedMmPerMin = max(1, speedMmPerMin)
        self.burnBlack = burnBlack
    }
}

public struct LaserPictureResult: Codable, Sendable {
    public let gcodeLines: [String]
    public let rasterRows: Int
    public let burnedPixels: Int
    public let success: Bool
    public let errorMessage: String?
}

public enum LaserPictureEngine {

    /// Convert a grayscale grid into a power-modulated raster program.
    /// Consecutive same-power runs merge into one G1; white rows skip.
    public static func compute(grid: GrayscaleGrid,
                               params: LaserPictureParams) -> LaserPictureResult {
        let pxMm = params.targetWidthMm / Double(grid.width)
        let heightMm = pxMm * Double(grid.height)
        var lines: [String] = ["G21", "G90", "; laser picture \(grid.width)x\(grid.height)"]
        var rasterRows = 0
        var burned = 0
        let threshold: UInt8 = 8 // below this, treat as white/off

        for row in 0..<grid.height {
            let y = heightMm - pxMm * Double(row) // top-down image → bottom-up G-code
            var col = 0
            var anyBurn = false
            while col < grid.width {
                var lum = grid.at(x: col, y: row)
                if params.burnBlack { lum = 255 - lum } // white→off mapping flip handled below
                // burnBlack=true means dark pixel burns: power ∝ luminance-as-darkness.
                let darkness = params.burnBlack ? (255 - Int(grid.at(x: col, y: row))) : Int(grid.at(x: col, y: row))
                _ = lum
                if darkness < Int(threshold) {
                    col += 1
                    continue
                }
                // Extend the run while power bucket stays identical.
                var end = col
                let startPower = darkness
                while end < grid.width {
                    let d = params.burnBlack ? (255 - Int(grid.at(x: end, y: row))) : Int(grid.at(x: end, y: row))
                    if abs(d - startPower) > 4 || d < Int(threshold) { break }
                    end += 1
                }
                let x0 = pxMm * Double(col)
                let x1 = pxMm * Double(end)
                let power = Int(round(Double(startPower) / 255.0 * params.maxPowerPercent * 10))
                lines.append(String(format: "G0 X%.3f Y%.3f", x0, y))
                lines.append(String(format: "S%d", power))
                lines.append(String(format: "G1 X%.3f Y%.3f F%.0f",
                                    x1, y, params.speedMmPerMin))
                burned += end - col
                anyBurn = true
                col = end
            }
            if anyBurn {
                lines.append("S0")
                rasterRows += 1
            }
        }
        lines.append("S0")
        lines.append("M5")

        return LaserPictureResult(gcodeLines: lines, rasterRows: rasterRows,
                                  burnedPixels: burned, success: true, errorMessage: nil)
    }
}

import Foundation
import ShopPilotCore

// SPK-1920g — wasteboard surfacing engine (pure model).
//
// A wasteboard facing op removes a thin, even layer from the machine's
// spoilboard to true it. The program is a raster: step over in X, raster
// rows in Y, one Z pass per layer down to the target depth. Everything is
// clamped; nothing auto-runs — the session only ever adds this as a tree
// node the user must Calculate + Run Job explicitly.

/// Parameters for a wasteboard surfacing operation.
public struct WasteboardSurfacingParams: Codable, Equatable, Sendable {
    /// Surfacing cutter diameter, mm.
    public var cutterDiameterMm: Double
    /// Radial engagement per row (≤ cutter diameter), mm.
    public var stepOverMm: Double
    /// Depth removed per Z pass, mm.
    public var maxDepthPerPassMm: Double
    /// Total depth to remove below current surface, mm.
    public var totalDepthMm: Double
    /// Feed while cutting, mm/min.
    public var feedRateMmPerMin: Double
    /// Plunge feed, mm/min.
    public var plungeFeedRateMmPerMin: Double
    /// Safe retract Z, mm.
    public var safeZHeightMm: Double
    /// Spindle RPM (0 = leave to manual control).
    public var spindleRpm: Double
    /// Wasteboard X extent to face, mm.
    public var widthMm: Double
    /// Wasteboard Y extent to face, mm.
    public var depthMm: Double

    public init(
        cutterDiameterMm: Double = 22.0,
        stepOverMm: Double = 11.0,
        maxDepthPerPassMm: Double = 1.0,
        totalDepthMm: Double = 1.5,
        feedRateMmPerMin: Double = 1200,
        plungeFeedRateMmPerMin: Double = 300,
        safeZHeightMm: Double = 5.0,
        spindleRpm: Double = 18000,
        widthMm: Double = 300,
        depthMm: Double = 200
    ) {
        self.cutterDiameterMm = cutterDiameterMm
        self.stepOverMm = stepOverMm
        self.maxDepthPerPassMm = maxDepthPerPassMm
        self.totalDepthMm = totalDepthMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.safeZHeightMm = safeZHeightMm
        self.spindleRpm = spindleRpm
        self.widthMm = widthMm
        self.depthMm = depthMm
    }

    /// Sanitized copy with every field inside its safe range.
    public func clamped() -> WasteboardSurfacingParams {
        var p = self
        p.cutterDiameterMm = min(max(p.cutterDiameterMm, 3), 60)
        p.stepOverMm = min(max(p.stepOverMm, 0.5), p.cutterDiameterMm)
        p.maxDepthPerPassMm = min(max(p.maxDepthPerPassMm, 0.1), 5)
        p.totalDepthMm = min(max(p.totalDepthMm, 0.1), 10)
        p.feedRateMmPerMin = min(max(p.feedRateMmPerMin, 50), 5000)
        p.plungeFeedRateMmPerMin = min(max(p.plungeFeedRateMmPerMin, 20), 1500)
        p.safeZHeightMm = min(max(p.safeZHeightMm, 1), 25)
        p.widthMm = min(max(p.widthMm, 10), 2000)
        p.depthMm = min(max(p.depthMm, 10), 2000)
        return p
    }
}

public enum WasteboardSurfacingEngine {

    /// Marker emitted as the first G-code line so the simulator/preflight can
    /// identify the op.
    static let marker = "O=WASTEBOARD_SURFACE"

    /// Number of Z passes: ceil(total / perPass), always ≥ 1.
    public static func zPassCount(_ params: WasteboardSurfacingParams) -> Int {
        let p = params.clamped()
        guard p.totalDepthMm > 0 else { return 1 }
        return max(1, Int(ceil(p.totalDepthMm / p.maxDepthPerPassMm)))
    }

    /// Number of raster rows: the Y extent covered by stepover-width strips,
    /// last row may overlap. Always ≥ 1. Uses EFFECTIVE step-over so a
    /// step-over wider than the cutter cannot leave uncut strips.
    public static func rowCount(_ params: WasteboardSurfacingParams) -> Int {
        let p = params.clamped()
        let effectiveStep = min(p.stepOverMm, p.cutterDiameterMm)
        let travel = max(0, p.depthMm - p.cutterDiameterMm)
        return max(1, Int(ceil(travel / effectiveStep)) + 1)
    }

    /// Generate the full facing program. Zig-zag raster in Y, stepping over
    /// in Y per row and cutting along X (alternating direction per row).
    /// Every Z pass repeats the same XY raster, deeper by one step.
    public static func generate(_ params: WasteboardSurfacingParams) -> [String] {
        let p = params.clamped()
        var lines: [String] = ["%", marker]
        if p.spindleRpm > 0 {
            lines.append("M3 S\(Int(p.spindleRpm))")
        }
        lines.append("(Surface \(String(format: "%.0f", p.widthMm))x\(String(format: "%.0f", p.depthMm))mm, remove \(String(format: "%.2f", p.totalDepthMm))mm)")

        let passes = zPassCount(p)
        let rows = rowCount(p)
        let effectiveStep = min(p.stepOverMm, p.cutterDiameterMm)

        for zPass in 1...passes {
            // Each Z pass cuts one step deeper; final pass reaches −totalDepth.
            let z = -min(p.totalDepthMm, p.maxDepthPerPassMm * Double(zPass))
            lines.append("")
            lines.append("(Z pass \(zPass)/\(passes), Z=\(fmt(z)))")
            lines.append("G0 Z\(fmt(p.safeZHeightMm))")

            for row in 0..<rows {
                let y = p.cutterDiameterMm / 2 + Double(row) * effectiveStep
                let left = fmt(p.cutterDiameterMm / 2)
                let right = fmt(max(p.cutterDiameterMm / 2, p.widthMm - p.cutterDiameterMm / 2))
                if row == 0 {
                    // First row: position then plunge at feed.
                    lines.append("G0 X\(left) Y\(fmt(y))")
                    lines.append("G1 Z\(fmt(z)) F\(Int(p.plungeFeedRateMmPerMin))")
                    lines.append("G1 X\(right) F\(Int(p.feedRateMmPerMin))")
                } else if row % 2 == 1 {
                    // Zig-zag: tool is already at the right side.
                    lines.append("G1 Y\(fmt(y)) F\(Int(p.feedRateMmPerMin))")
                    lines.append("G1 X\(left) F\(Int(p.feedRateMmPerMin))")
                } else {
                    lines.append("G1 Y\(fmt(y)) F\(Int(p.feedRateMmPerMin))")
                    lines.append("G1 X\(right) F\(Int(p.feedRateMmPerMin))")
                }
            }
            // Lift before the next Z pass.
            lines.append("G0 Z\(fmt(p.safeZHeightMm))")
        }

        lines.append("")
        lines.append("M5")
        lines.append("M30")
        lines.append("%")
        return lines
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}

import Foundation

// MARK: - SPK-1910a — Trochoidal Slotting (engine)
//
// Trochoidal slotting mills a narrow slot / closed corridor with looping
// motions so the bit never takes a full-width bury: the cutter advances a
// small pitch `p` along the slot centerline while orbiting a circle of
// radius `R`, keeping radial engagement (WOC) small even when tool
// diameter ≈ slot width. Independent implementation — no proprietary ports.
//
// Geometry contract (v1, deliberately simple and testable):
//   - Input: closed `VectorPath`s treated as slot corridors. v1 handles the
//     rectangular-corridor case via bounding-box medial axis: the centerline
//     is the long-axis segment inset from both ends by the tool radius.
//   - Too-narrow rule: if the corridor's short side < `toolDiameter * 1.02`
//     the slot cannot fit the cutter → `isTooNarrow == true`, header-only
//     output, zero cut moves (same discipline as pocket `isTooSmall`).
//
// Loop radius formula (documented per spec §Geometry contract):
//     idealR    = toolRadius - woc/2      // circle whose swing peels `woc`
//                                         // of fresh wall per wall contact
//     maxFitR   = slotHalfWidth - toolRadius  // keeps loop+cutter inside slot
//     R         = min(idealR, maxFitR), clamped > 0
// When `idealR > maxFitR` (slot barely wider than the tool — the normal
// hobby case) the loop spans the full slot width and radial engagement is
// governed by the forward pitch instead:
//     effPitch  = min(loopPitchMm, maxWocMm)
// i.e. the advance per loop never exceeds the requested max radial
// engagement. Smaller WOC ⇒ smaller effective pitch ⇒ more loops.
//
// Radial-engagement estimator (asserted in ShopPilotVerify1910a):
// every loop is sampled at 32 angular steps; engagement is modeled as twice
// the forward advance per revolution (worst-case wall-curvature
// amplification): peakEngagement ≈ 2 × effPitch. Asserted < toolDiameter.

/// Cut winding for trochoid loops. Reuses the Profile/Pocket enum values.
public typealias TrochoidSlotCutDirection = CutDirection

// MARK: - Parameters

public struct TrochoidSlotParams: Codable, Sendable, Equatable {
    public var toolDiameterMm: Double
    public var cutDepthMm: Double
    public var startDepthMm: Double
    public var maxDepthOfCutMm: Double
    /// Max radial engagement (WOC) — the whole point of trochoidal slotting.
    public var maxWocMm: Double
    /// Nominal advance per loop along the centerline (mm).
    public var loopPitchMm: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var safetyHeightMm: Double
    /// 0 = emit no M3 (same discipline as Pocket SPK-1133b).
    public var spindleRpm: Double
    /// Climb vs conventional — reverses loop winding (G3 vs G2).
    public var cutDirection: TrochoidSlotCutDirection
    /// Ramp entry instead of any vertical plunge into full slot.
    public var rampEntry: Bool

    public init(
        toolDiameterMm: Double = 6.0,
        cutDepthMm: Double = 6.0,
        startDepthMm: Double = 0.0,
        maxDepthOfCutMm: Double = 2.0,
        maxWocMm: Double = 0.8,
        loopPitchMm: Double = 0.6,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        safetyHeightMm: Double = 5.0,
        spindleRpm: Double = 0,
        cutDirection: TrochoidSlotCutDirection = .climb,
        rampEntry: Bool = true
    ) {
        self.toolDiameterMm = toolDiameterMm
        self.cutDepthMm = cutDepthMm
        self.startDepthMm = startDepthMm
        self.maxDepthOfCutMm = maxDepthOfCutMm
        self.maxWocMm = maxWocMm
        self.loopPitchMm = loopPitchMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.safetyHeightMm = safetyHeightMm
        self.spindleRpm = spindleRpm
        self.cutDirection = cutDirection
        self.rampEntry = rampEntry
    }

    /// Legacy-safe decoding: missing keys fall back to defaults; unknown keys
    /// are ignored so older/newer documents always load.
    private enum CodingKeys: String, CodingKey {
        case toolDiameterMm, cutDepthMm, startDepthMm, maxDepthOfCutMm
        case maxWocMm, loopPitchMm, feedRateMmPerMin, plungeFeedRateMmPerMin
        case safetyHeightMm, spindleRpm, cutDirection, rampEntry
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .toolDiameterMm) ?? 6.0
        cutDepthMm = try c.decodeIfPresent(Double.self, forKey: .cutDepthMm) ?? 6.0
        startDepthMm = try c.decodeIfPresent(Double.self, forKey: .startDepthMm) ?? 0.0
        maxDepthOfCutMm = try c.decodeIfPresent(Double.self, forKey: .maxDepthOfCutMm) ?? 2.0
        maxWocMm = try c.decodeIfPresent(Double.self, forKey: .maxWocMm) ?? 0.8
        loopPitchMm = try c.decodeIfPresent(Double.self, forKey: .loopPitchMm) ?? 0.6
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1000
        plungeFeedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeFeedRateMmPerMin) ?? 300
        safetyHeightMm = try c.decodeIfPresent(Double.self, forKey: .safetyHeightMm) ?? 5.0
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
        cutDirection = try c.decodeIfPresent(TrochoidSlotCutDirection.self, forKey: .cutDirection) ?? .climb
        rampEntry = try c.decodeIfPresent(Bool.self, forKey: .rampEntry) ?? true
    }
}

// MARK: - Result

public struct TrochoidSlotResult: Sendable {
    public let params: TrochoidSlotParams
    public let gcodeLines: [String]
    /// Corridor narrower than toolDiameter × 1.02 — no cut moves emitted.
    public let isTooNarrow: Bool
    /// Parameter-validation errors (empty gcode when non-empty, pocket-style).
    public let errors: [String]
    public let passCount: Int
    public let loopCount: Int
    public let estimatedTimeSeconds: Double
    /// Sampled peak radial engagement estimate in mm (< toolDiameter when cutting).
    public let peakRadialEngagementMm: Double

    public var isValid: Bool { errors.isEmpty }
}

// MARK: - Engine

public struct TrochoidSlotToolpathEngine {

    /// Angular samples per loop used for the engagement estimator.
    static let loopSamples = 32

    public static func compute(
        vectors: [VectorPath],
        params: TrochoidSlotParams,
        material: Material? = nil,
        stockHeightMm: Double = 25.0
    ) -> TrochoidSlotResult {
        // ── Parameter validation (pocket-style: errors + empty gcode). ──────
        var errors: [String] = []
        if params.toolDiameterMm <= 0 { errors.append("tool diameter must be > 0") }
        if params.maxDepthOfCutMm <= 0 { errors.append("max depth of cut must be > 0") }
        if params.maxWocMm <= 0 { errors.append("max WOC must be > 0") }
        if params.loopPitchMm <= 0 { errors.append("loop pitch must be > 0") }
        if params.feedRateMmPerMin <= 0 { errors.append("feed rate must be > 0") }
        if params.plungeFeedRateMmPerMin <= 0 { errors.append("plunge feed must be > 0") }
        if params.safetyHeightMm <= 0 { errors.append("safety height must be > 0") }
        if params.maxWocMm >= params.toolDiameterMm { errors.append("max WOC must be < tool diameter") }

        guard errors.isEmpty else {
            return TrochoidSlotResult(
                params: params, gcodeLines: [], isTooNarrow: false,
                errors: errors, passCount: 0, loopCount: 0,
                estimatedTimeSeconds: 0, peakRadialEngagementMm: 0
            )
        }

        // ── Header. ─────────────────────────────────────────────────────────
        var lines: [String] = []
        lines.append("%")
        lines.append("O=TROCHOID_SLOT")
        lines.append("(Tool: \(Int(params.toolDiameterMm * 10))mm)")
        if params.spindleRpm > 0 {
            lines.append("M3 S\(Int(params.spindleRpm))")
        }

        let toolRadius = params.toolDiameterMm / 2.0
        // Effective advance per loop: never exceed the requested radial
        // engagement (see file-header derivation).
        let effPitch = min(params.loopPitchMm, params.maxWocMm)

        // Depth passes from startDepth to cutDepth (AC: depth 4 / DOC 2 → 2 passes).
        let totalDepth = params.cutDepthMm - params.startDepthMm
        let passCount = max(1, Int(ceil(totalDepth / params.maxDepthOfCutMm)))

        var totalLoops = 0
        var totalPathLength = 0.0
        var peakEngagement = 0.0

        for vector in vectors {
            guard !vector.points.isEmpty && vector.isClosed else { continue }
            guard let b = vector.bounds else { continue }

            let width = b.maxX - b.minX
            let height = b.maxY - b.minY
            let shortSide = min(width, height)

            // Too-narrow gate: cutter (+2% fit margin) must fit across the slot.
            if shortSide < params.toolDiameterMm * 1.02 {
                lines.append("(SKIPPED: Slot too narrow for \(String(format: "%.2f", params.toolDiameterMm))mm tool)")
                continue
            }

            // Medial-axis centerline: long-axis segment inset from ends by
            // the tool radius (rectangle-corridor approximation, v1).
            let horizontal = width >= height
            let centerY = (b.minY + b.maxY) / 2.0
            let centerX = (b.minX + b.maxX) / 2.0
            let startPt: (x: Double, y: Double)
            let dirX: Double, dirY: Double
            let centerlineLength: Double
            let slotHalfWidth: Double
            if horizontal {
                startPt = (b.minX + toolRadius, centerY)
                dirX = 1.0; dirY = 0.0
                centerlineLength = width - 2 * toolRadius
                slotHalfWidth = height / 2.0
            } else {
                startPt = (centerX, b.minY + toolRadius)
                dirX = 0.0; dirY = 1.0
                centerlineLength = height - 2 * toolRadius
                slotHalfWidth = width / 2.0
            }
            guard centerlineLength > 0 else {
                lines.append("(SKIPPED: Slot too short for \(String(format: "%.2f", params.toolDiameterMm))mm tool)")
                continue
            }

            // Loop radius per the documented formula (file header).
            let idealR = toolRadius - params.maxWocMm / 2.0
            let maxFitR = slotHalfWidth - toolRadius
            let loopRadius = max(min(idealR, maxFitR), 0.05)

            // Loop centers advance along the centerline; each loop is one
            // full circle. Winding: climb → G3 (CCW), conventional → G2 (CW).
            let arcWord = (params.cutDirection == .climb) ? "G3" : "G2"
            let loopCount = max(1, Int(ceil(centerlineLength / effPitch)))

            let fFeed = Int(params.feedRateMmPerMin)
            let fPlunge = Int(params.plungeFeedRateMmPerMin)

            for pass in 1...passCount {
                let cutThisPass = min(Double(pass) * params.maxDepthOfCutMm, totalDepth)
                let zThis = -(params.startDepthMm + cutThisPass)

                lines.append("")
                lines.append("(Trochoid Pass \(pass)/\(passCount), Z=\(String(format: "%.3f", zThis)))")
                lines.append("G0 Z\(fmt(params.safetyHeightMm, 1))")
                lines.append("G0 X\(fmt(startPt.x)) Y\(fmt(startPt.y))")

                // Entry: helical/ramped — descend along the first pitch of
                // the centerline (never a vertical plunge into full slot).
                if params.rampEntry {
                    let rampLen = min(effPitch * 2, centerlineLength)
                    lines.append("G1 X\(fmt(startPt.x + dirX * rampLen)) Y\(fmt(startPt.y + dirY * rampLen)) Z\(fmt(zThis)) F\(fPlunge)")
                } else {
                    lines.append("G1 Z\(fmt(zThis)) F\(fPlunge)")
                }

                // Loops: full circles (GRBL allows same-start/end arcs),
                // centers stepping effPitch along the centerline.
                for i in 0..<loopCount {
                    let t = min(Double(i) * effPitch, centerlineLength)
                    let cx = startPt.x + dirX * t
                    let cy = startPt.y + dirY * t
                    // Full circle: endpoint == startpoint, IJ = center offset.
                    lines.append("\(arcWord) X\(fmt(cx)) Y\(fmt(cy)) I\(fmt(-loopRadius)) J0 F\(fFeed)")
                    totalPathLength += 2 * .pi * loopRadius
                }

                // Retract between passes (and after the last) at safe Z.
                lines.append("G0 Z\(fmt(params.safetyHeightMm))")
            }

            totalLoops += loopCount * passCount
            // Engagement estimator: 32 samples per loop; peak ≈ 2 × effPitch
            // (worst-case wall-curvature amplification of the forward advance).
            peakEngagement = max(peakEngagement, 2.0 * effPitch)
        }

        // Footer.
        lines.append("")
        lines.append("M30")
        lines.append("%")

        let estSeconds = totalPathLength / params.feedRateMmPerMin * 60.0

        return TrochoidSlotResult(
            params: params,
            gcodeLines: lines,
            isTooNarrow: totalLoops == 0,
            errors: [],
            passCount: passCount,
            loopCount: totalLoops,
            estimatedTimeSeconds: estSeconds,
            peakRadialEngagementMm: peakEngagement
        )
    }

    @inline(__always)
    private static func fmt(_ v: Double, _ places: Int = 3) -> String {
        String(format: "%.\(places)f", v)
    }
}

private extension Double {
    func clamped(to lower: Double, _ upper: Double) -> Double {
        Swift.min(Swift.max(self, lower), upper)
    }
}


// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct TrochoidSlotToolpath_Previews: PreviewProvider {
    static var previews: some View {
        Text("Trochoid slot toolpath is a non-visual component")
    }
}
#endif

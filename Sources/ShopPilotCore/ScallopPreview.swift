import Foundation

// MARK: - SPK-2100c — Scallop-leftover preview tint (honest, formula-based)
//
// The Finish 3D preview must tell the user how much material a ball-nose
// raster will LEAVE BETWEEN PASSES, not paint a photoreal metal render.
// For shallow ball lace the cusp (scallop) height between adjacent passes is
// the classic geometric approximation:
//
//     h ≈ s² / (8R)        s = step-over, R = ball radius = D/2
//
// The number is compared against a 0.02 mm "shop quality" band and drives an
// honest formula TINT (green inside the band, warming to red as the leftover
// grows past it). Nothing here renders shaded metal — it is a color derived
// from two numbers and a threshold, so the preview updates the instant the
// step-over changes. If the operation carries rough stock-to-leave, that
// allowance is ADDED to the leftover: the finish pass cannot remove stock the
// rough pass was told to leave.

/// SPK-2100c — shared "shop quality" thresholds for finish leftovers.
public enum ScallopShopBand {
    /// A 0.02 mm cusp height is the common shop-quality finish band for
    /// surface work (≈ 8 µm is mirror; 50 µm on a 25%-of-D stepover is not).
    public static let shopQualityMm: Double = 0.02

    /// Severity at which the tint saturates fully red (5× the shop band).
    public static let saturationSeverity: Double = 5.0
}

/// SPK-2100c — the honest scallop-leftover verdict for one finish op:
/// the formula numbers, whether they fit the 0.02 mm shop band, and the
/// derived tint color. Pure value math — no rendering, no photorealism.
public struct ScallopLeftoverTint: Equatable, Sendable {
    /// Step-over the verdict was computed from (mm).
    public let stepOverMm: Double
    /// Ball tool diameter the verdict was computed from (mm).
    public let toolDiameterMm: Double
    /// Rough stock-to-leave honored from the op, when present (mm).
    public let roughStockToLeaveMm: Double
    /// Cusp scallop between passes: h ≈ s²/(8R).
    public let scallopHeightMm: Double
    /// What actually remains above the ideal surface: scallop + stock-to-leave.
    public let totalLeftoverMm: Double
    /// True when the TOTAL leftover fits the 0.02 mm shop band.
    public let withinShopBand: Bool
    /// totalLeftover / shopBand (≥ 0). 1.0 == exactly at the band edge.
    public let severity: Double

    public static func compute(
        stepOverMm: Double,
        toolDiameterMm: Double,
        roughStockToLeaveMm: Double = 0
    ) -> ScallopLeftoverTint {
        let r = max(1e-9, toolDiameterMm * 0.5)
        let s = max(0, stepOverMm)
        let leave = max(0, roughStockToLeaveMm)
        let scallop = (s * s) / (8.0 * r)
        let total = scallop + leave
        let severity = total / ScallopShopBand.shopQualityMm
        // Band-edge tolerance: a step-over derived as sqrt(band·8R) then
        // squared lands at severity ≈ 1 + 1e-16 in floating point; the
        // documented contract is that exactly-at-band IS in-band, so compare
        // with a relative epsilon instead of a bare `<= 1.0`.
        return ScallopLeftoverTint(
            stepOverMm: s,
            toolDiameterMm: toolDiameterMm,
            roughStockToLeaveMm: leave,
            scallopHeightMm: scallop,
            totalLeftoverMm: total,
            withinShopBand: severity <= 1.0 + 1e-9,
            severity: max(0, severity)
        )
    }

    // MARK: Honest formula tint (NOT photoreal)

    /// RGB in 0…1. Inside the band: calm green. Past the band: a linear ramp
    /// green → amber → red driven by `severity`, saturating at
    /// `ScallopShopBand.saturationSeverity`. This is a color computed FROM
    /// the formula — there is no lighting, shading, or metal look involved.
    public var tintRGB: (r: Double, g: Double, b: Double) {
        if severity <= 1.0 { return (0.20, 0.78, 0.31) }           // in band: green
        let t = min(1.0, (severity - 1.0) / (ScallopShopBand.saturationSeverity - 1.0))
        // Green (0.20, 0.78, 0.31) → amber (0.95, 0.72, 0.10) at t = 0.5,
        // then amber → red (0.96, 0.16, 0.13). Piecewise-linear so the mid
        // of the ramp reads as a warning amber, not muddy brown. The red
        // channel only ever RISES along the whole ramp (0.20 → 0.95 → 0.96)
        // and green only FALLS (0.78 → 0.72 → 0.16) — the tint must never
        // recede as the leftover grows.
        let green = (r: 0.20, g: 0.78, b: 0.31)
        let amber = (r: 0.95, g: 0.72, b: 0.10)
        let red   = (r: 0.96, g: 0.16, b: 0.13)
        func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }
        if t <= 0.5 {
            let k = t / 0.5
            return (lerp(green.r, amber.r, k), lerp(green.g, amber.g, k), lerp(green.b, amber.b, k))
        }
        let k = (t - 0.5) / 0.5
        return (lerp(amber.r, red.r, k), lerp(amber.g, red.g, k), lerp(amber.b, red.b, k))
    }

    /// One RGBA8888 pixel of the tint (alpha 200 ≈ 78% — an overlay wash,
    /// never an opaque repaint of the relief).
    public var rgba8888: [UInt8] {
        let c = tintRGB
        return [UInt8((c.r * 255).rounded()),
                UInt8((c.g * 255).rounded()),
                UInt8((c.b * 255).rounded()),
                200]
    }

    /// A uniform RGBA overlay raster (`width × height` pixels, 4 bytes each)
    /// in the tint color. The Preview stage composites this over the sim so
    /// the WHOLE cut area carries the leftover verdict.
    public func overlayPixels(width: Int, height: Int) -> [UInt8] {
        let px = rgba8888
        return Array(repeating: px, count: max(0, width) * max(0, height)).flatMap { $0 }
    }

    /// Human-readable legend shown next to the tint — always states the
    /// formula inputs and the band so the readout stays honest.
    public var legendText: String {
        let base = String(
            format: "Scallop h ≈ %.4f mm (s=%.3f, Ø=%.3f) vs %.2f mm shop band",
            scallopHeightMm, stepOverMm, toolDiameterMm, ScallopShopBand.shopQualityMm)
        if roughStockToLeaveMm > 0 {
            return base + String(format: " + %.3f mm stock-to-leave = %.4f mm left", roughStockToLeaveMm, totalLeftoverMm)
        }
        return base
    }

    /// Short verdict word for the legend chip.
    public var verdictText: String {
        withinShopBand ? "In shop band" : "Over shop band"
    }
}

public extension HeightfieldFinishParams {
    /// SPK-2100c — the scallop verdict for these finish params. Pass the
    /// rough stock-to-leave when the job's Rough 3D op carries one; the
    /// finish cannot machine below what roughing left behind.
    func leftoverTint(roughStockToLeaveMm: Double = 0) -> ScallopLeftoverTint {
        ScallopLeftoverTint.compute(
            stepOverMm: stepOverMm,
            toolDiameterMm: toolDiameterMm,
            roughStockToLeaveMm: roughStockToLeaveMm)
    }
}

import Foundation

// MARK: - Material surface palette (SPK-1202)

/// Material look for the preview: the stock's SKIN color on top, the BASE
/// color revealed once the cut passes through the surface layers — the
/// "cutting through painted/laminated material" look Aspire 12.5 ships.
/// Pure data + math — CLT-verifiable.
public struct MaterialSurfacePalette: Sendable {
    /// Material display name (walnut, acrylic, painted MDF, plywood…).
    public let name: String
    /// Top skin color (RGB 0…1) — what the uncut surface looks like.
    public let topColor: (r: Double, g: Double, b: Double)
    /// Base color revealed at depth.
    public let baseColor: (r: Double, g: Double, b: Double)
    /// How many surface layers exist before the base shows (paint = 1,
    /// laminate = 2, plywood = 0).
    public let surfaceLayers: Int

    public init(name: String,
                topColor: (r: Double, g: Double, b: Double),
                baseColor: (r: Double, g: Double, b: Double),
                surfaceLayers: Int) {
        self.name = name
        self.topColor = topColor
        self.baseColor = baseColor
        self.surfaceLayers = max(0, surfaceLayers)
    }

    /// Interpolated color at a given cut fraction (0 = surface, 1 = deepest
    /// cut). The skin persists for the first `surfaceLayers / 4` of depth
    /// (each layer ≈ 25% of the max cut), then blends to the base.
    public func color(atDepthFraction fraction: Double) -> (r: Double, g: Double, b: Double) {
        let f = min(1, max(0, fraction))
        let skinSpan = Double(surfaceLayers) / 4.0
        let t: Double
        if f <= skinSpan {
            t = 0
        } else if skinSpan >= 1 {
            t = 0
        } else {
            t = (f - skinSpan) / (1 - skinSpan)
        }
        return (
            r: topColor.r + (baseColor.r - topColor.r) * t,
            g: topColor.g + (baseColor.g - topColor.g) * t,
            b: topColor.b + (baseColor.b - topColor.b) * t
        )
    }

    /// Built-in presets (the preview material picker's list).
    public static let presets: [MaterialSurfacePalette] = [
        MaterialSurfacePalette(
            name: "Walnut",
            topColor: (0.45, 0.28, 0.13),
            baseColor: (0.30, 0.17, 0.08),
            surfaceLayers: 1
        ),
        MaterialSurfacePalette(
            name: "Painted MDF",
            topColor: (0.95, 0.95, 0.96),
            baseColor: (0.72, 0.62, 0.50),
            surfaceLayers: 1
        ),
        MaterialSurfacePalette(
            name: "Acrylic",
            topColor: (0.25, 0.65, 0.90),
            baseColor: (0.60, 0.80, 0.95),
            surfaceLayers: 0
        ),
        MaterialSurfacePalette(
            name: "Plywood",
            topColor: (0.80, 0.66, 0.44),
            baseColor: (0.58, 0.42, 0.24),
            surfaceLayers: 2
        ),
    ]

    public static func preset(named name: String) -> MaterialSurfacePalette? {
        presets.first { $0.name == name }
    }
}

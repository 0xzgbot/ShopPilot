import Foundation

// MARK: - Sculpt Engine (SPK-0713 lean slice)

/// One sculpt brush stroke applied to the document heightfield. Center is in
/// world mm; the brush affects every cell whose cell-center distance is
/// within `radiusMm` of the stroke center.
public struct SculptStrokeParams: Codable, Sendable {
    public var tool: SculptTool
    public var centerX: Double        // world mm
    public var centerY: Double        // world mm
    public var radiusMm: Double
    public var strength: Double       // signed −1…1 (negative lowers for brush)
    public var maxDeltaMm: Double     // full-strength height change per stroke
    public var brushShape: BrushShape
    public var brushFalloff: BrushFalloff

    public init(
        tool: SculptTool = .brush,
        centerX: Double = 0,
        centerY: Double = 0,
        radiusMm: Double = 5.0,
        strength: Double = 0.5,
        maxDeltaMm: Double = 2.0,
        brushShape: BrushShape = .sphere,
        brushFalloff: BrushFalloff = .smooth
    ) {
        self.tool = tool
        self.centerX = centerX
        self.centerY = centerY
        self.radiusMm = max(0.1, radiusMm)
        self.strength = max(-1.0, min(1.0, strength))
        self.maxDeltaMm = max(0.0, maxDeltaMm)
        self.brushShape = brushShape
        self.brushFalloff = brushFalloff
    }

    private enum CodingKeys: String, CodingKey {
        case tool, centerX, centerY, radiusMm, strength, maxDeltaMm
        case brushShape, brushFalloff
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tool = try c.decodeIfPresent(SculptTool.self, forKey: .tool) ?? .brush
        centerX = try c.decodeIfPresent(Double.self, forKey: .centerX) ?? 0
        centerY = try c.decodeIfPresent(Double.self, forKey: .centerY) ?? 0
        radiusMm = try c.decodeIfPresent(Double.self, forKey: .radiusMm) ?? 5.0
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? 0.5
        maxDeltaMm = try c.decodeIfPresent(Double.self, forKey: .maxDeltaMm) ?? 2.0
        brushShape = try c.decodeIfPresent(BrushShape.self, forKey: .brushShape) ?? .sphere
        brushFalloff = try c.decodeIfPresent(BrushFalloff.self, forKey: .brushFalloff) ?? .smooth
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tool, forKey: .tool)
        try c.encode(centerX, forKey: .centerX)
        try c.encode(centerY, forKey: .centerY)
        try c.encode(radiusMm, forKey: .radiusMm)
        try c.encode(strength, forKey: .strength)
        try c.encode(maxDeltaMm, forKey: .maxDeltaMm)
        try c.encode(brushShape, forKey: .brushShape)
        try c.encode(brushFalloff, forKey: .brushFalloff)
    }
}

public struct SculptStrokeResult: Codable, Sendable {
    public let heightfield: HeightfieldData
    public let cellsAffected: Int
    public let minHeight: Double
    public let maxHeight: Double

    public init(heightfield: HeightfieldData, cellsAffected: Int, minHeight: Double, maxHeight: Double) {
        self.heightfield = heightfield
        self.cellsAffected = cellsAffected
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }
}

/// Pure heightfield sculpting: every tool returns a NEW `HeightfieldData`
/// (the input is immutable — `heights` is `let`), touching only cells inside
/// the brush radius. The tool semantics:
///   - brush:   h += strength · w · maxDelta        (signed: negative lowers)
///   - inflate: h += |strength| · w · maxDelta
///   - deflate: h −= |strength| · w · maxDelta
///   - flatten: pull toward the mean height of the brush footprint
///   - smooth:  blend toward the local 4-neighbour average
///   - pinch:   pull toward the height at the brush center
///   - grab:    h += strength · w · maxDelta (move the surface along with
///              the cursor — same arithmetic as brush, distinct UX)
/// Heights are clamped to ≥ 0 (the stock floor).
public enum SculptEngine {

    /// Falloff weight at normalized distance t ∈ [0, 1] (0 = center).
    /// Shape picks the profile, falloff the edge roll-off.
    public static func falloffWeight(
        t: Double,
        shape: BrushShape,
        falloff: BrushFalloff
    ) -> Double {
        let tt = max(0.0, min(1.0, t))
        // Profile by shape: sphere is a dome (strongest at center, gentle
        // edge); cylinder/flat are constant across the footprint.
        let profile: Double
        switch shape {
        case .sphere:
            profile = (1 - tt * tt).squareRoot()
        case .cylinder, .flat, .custom:
            profile = 1.0
        }
        // Edge roll-off by falloff curve.
        let edge: Double
        switch falloff {
        case .linear:
            edge = 1 - tt
        case .smooth:          // smoothstep
            let u = 1 - tt
            edge = u * u * (3 - 2 * u)
        case .constant:
            edge = 1.0
        case .root:
            edge = (1 - tt).squareRoot()
        }
        return profile * edge
    }

    /// Apply one stroke. Cells outside the radius keep their exact heights.
    public static func applyStroke(
        _ stroke: SculptStrokeParams,
        to hf: HeightfieldData
    ) -> SculptStrokeResult {
        guard hf.width > 0, hf.height > 0, hf.heights.count == hf.width * hf.height else {
            return SculptStrokeResult(heightfield: hf, cellsAffected: 0,
                                      minHeight: hf.heights.min() ?? 0,
                                      maxHeight: hf.maxHeight)
        }

        var out = hf.heights
        var affected = 0
        let r = stroke.radiusMm
        let cell = hf.cellSizeMm

        // Bounding box of the brush in cell space (inclusive, clamped).
        let minCellX = max(0, Int(((stroke.centerX - r) - hf.minX) / cell))
        let maxCellX = min(hf.width - 1, Int(((stroke.centerX + r) - hf.minX) / cell))
        let minCellY = max(0, Int(((stroke.centerY - r) - hf.minY) / cell))
        let maxCellY = min(hf.height - 1, Int(((stroke.centerY + r) - hf.minY) / cell))

        // Pre-compute the mean footprint height for flatten, and the center
        // height for pinch, from the ORIGINAL grid (deterministic per stroke).
        var footprintSum = 0.0
        var footprintCount = 0
        var centerHeight = 0.0
        var foundCenter = false
        if stroke.tool == .flatten {
            for j in minCellY...maxCellY {
                for i in minCellX...maxCellX {
                    footprintSum += out[j * hf.width + i]
                    footprintCount += 1
                }
            }
        }
        if stroke.tool == .pinch {
            if let ch = hf.height(atX: stroke.centerX, y: stroke.centerY) {
                centerHeight = ch
                foundCenter = true
            }
        }
        let footprintMean = footprintCount > 0 ? footprintSum / Double(footprintCount) : 0

        for j in minCellY...maxCellY {
            for i in minCellX...maxCellX {
                let cx = hf.minX + (Double(i) + 0.5) * cell
                let cy = hf.minY + (Double(j) + 0.5) * cell
                let dx = cx - stroke.centerX
                let dy = cy - stroke.centerY
                let dist = (dx * dx + dy * dy).squareRoot()
                guard dist <= r else { continue }

                let w = falloffWeight(t: dist / r, shape: stroke.brushShape, falloff: stroke.brushFalloff)
                guard w > 1e-9 else { continue }
                let idx = j * hf.width + i
                let h = out[idx]
                let strength = stroke.strength
                let delta = stroke.maxDeltaMm

                switch stroke.tool {
                case .brush, .grab:
                    out[idx] = max(0, h + strength * w * delta)
                case .inflate:
                    out[idx] = max(0, h + abs(strength) * w * delta)
                case .deflate:
                    out[idx] = max(0, h - abs(strength) * w * delta)
                case .flatten:
                    out[idx] = max(0, h + (footprintMean - h) * abs(strength) * w)
                case .smooth:
                    let avg = localAverage(out, hf: hf, i: i, j: j)
                    out[idx] = max(0, h + (avg - h) * abs(strength) * w)
                case .pinch:
                    if foundCenter {
                        out[idx] = max(0, h + (centerHeight - h) * abs(strength) * w)
                    }
                }
                if abs(out[idx] - h) > 1e-12 {
                    affected += 1
                }
            }
        }

        let newHF = HeightfieldData(
            width: hf.width, height: hf.height,
            cellSizeMm: hf.cellSizeMm,
            minX: hf.minX, minY: hf.minY,
            heights: out
        )
        return SculptStrokeResult(
            heightfield: newHF,
            cellsAffected: affected,
            minHeight: out.min() ?? 0,
            maxHeight: out.max() ?? 0
        )
    }

    /// 4-neighbour average; edge cells average their available neighbours.
    /// Used by the smooth tool's blend target.
    static func localAverage(_ heights: [Double], hf: HeightfieldData, i: Int, j: Int) -> Double {
        var sum = 0.0
        var n = 0
        for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let ni = i + di
            let nj = j + dj
            if ni >= 0, ni < hf.width, nj >= 0, nj < hf.height {
                sum += heights[nj * hf.width + ni]
                n += 1
            }
        }
        if n == 0 { return heights[j * hf.width + i] }
        return sum / Double(n)
    }
}

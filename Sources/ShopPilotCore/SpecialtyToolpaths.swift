import Foundation

// MARK: - Specialty strategies (SPK-0900 lean slices + SPK-0802 inlay)

/// Boundary helpers shared by the specialty engines: extract a closed polygon
/// from a VectorPath and compute the inside runs of a horizontal scanline.
public enum SpecialtyBoundary {

    /// Closed polygon points for a path. Open paths are closed by appending
    /// the first point; degenerate paths (< 3 points) return nil.
    public static func polygonPoints(of path: VectorPath) -> [VectorPoint]? {
        guard path.points.count >= 3 else { return nil }
        if path.isClosed {
            // Ensure the loop is explicitly closed (first == last) for the
            // crossing algorithm.
            if path.points.first == path.points.last {
                return path.points
            }
            return path.points + [path.points[0]]
        }
        return path.points + [path.points[0]]
    }

    /// Inside runs [x0, x1] of the horizontal line y = const within the
    /// polygon (even-odd rule). Half-open edge test [minY, maxY) avoids
    /// double-counting vertices. Runs are sorted left to right.
    public static func insideRuns(of polygon: [VectorPoint], y: Double) -> [(x0: Double, x1: Double)] {
        guard polygon.count >= 3 else { return [] }
        var crossings: [Double] = []
        let n = polygon.count - 1   // polygon is explicitly closed (last == first)
        for i in 0..<n {
            let a = polygon[i]
            let b = polygon[i + 1]
            let ay = a.y, by = b.y
            guard ay != by else { continue }   // horizontal edge: skip
            if (ay <= y && by > y) || (by <= y && ay > y) {
                let t = (y - ay) / (by - ay)
                crossings.append(a.x + t * (b.x - a.x))
            }
        }
        crossings.sort()
        var runs: [(x0: Double, x1: Double)] = []
        var i = 0
        while i + 1 < crossings.count {
            let x0 = crossings[i]
            let x1 = crossings[i + 1]
            if x1 - x0 > 1e-9 {
                runs.append((x0, x1))
            }
            i += 2
        }
        return runs
    }
}

// MARK: - Prism (F10)

/// Parallel V-grooves across selected closed vectors: the classic prismatic
/// light-catching sign surface. Groove depth = min(runWidth, spacing) /
/// (2·tan(θ/2)) so adjacent grooves just meet at the bottom; rows narrower
/// than the spacing cut shallower (boundary taper).
public struct PrismToolpathParams: Codable, Sendable {
    public var spacingMm: Double
    public var vBitAngleDegrees: Double
    public var maxDepthMm: Double      // 0 = uncapped (spacing-derived)
    public var startDepthMm: Double
    public var safeZHeightMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var spindleRpm: Double

    public init(
        spacingMm: Double = 6.0,
        vBitAngleDegrees: Double = 90.0,
        maxDepthMm: Double = 0,
        startDepthMm: Double = 0,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1500,
        plungeRateMmPerMin: Double = 300,
        spindleRpm: Double = 0
    ) {
        self.spacingMm = spacingMm
        self.vBitAngleDegrees = vBitAngleDegrees
        self.maxDepthMm = maxDepthMm
        self.startDepthMm = startDepthMm
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.spindleRpm = spindleRpm
    }

    private enum CodingKeys: String, CodingKey {
        case spacingMm, vBitAngleDegrees, maxDepthMm, startDepthMm
        case safeZHeightMm, feedRateMmPerMin, plungeRateMmPerMin, spindleRpm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spacingMm = try c.decodeIfPresent(Double.self, forKey: .spacingMm) ?? 6.0
        vBitAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .vBitAngleDegrees) ?? 90.0
        maxDepthMm = try c.decodeIfPresent(Double.self, forKey: .maxDepthMm) ?? 0
        startDepthMm = try c.decodeIfPresent(Double.self, forKey: .startDepthMm) ?? 0
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1500
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(spacingMm, forKey: .spacingMm)
        try c.encode(vBitAngleDegrees, forKey: .vBitAngleDegrees)
        try c.encode(maxDepthMm, forKey: .maxDepthMm)
        try c.encode(startDepthMm, forKey: .startDepthMm)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(spindleRpm, forKey: .spindleRpm)
    }
}

public struct SpecialtyResult: Codable, Sendable {
    public let gcodeLines: [String]
    public let estimatedTimeSeconds: Double
    public let featureCount: Int

    public init(gcodeLines: [String], estimatedTimeSeconds: Double, featureCount: Int) {
        self.gcodeLines = gcodeLines
        self.estimatedTimeSeconds = estimatedTimeSeconds
        self.featureCount = featureCount
    }
}

public enum PrismToolpathEngine {

    /// Prism-cut every closed path: parallel V-grooves across each boundary.
    public static func compute(
        paths: [VectorPath],
        params: PrismToolpathParams,
        stockHeightMm: Double = 25.0
    ) -> SpecialtyResult {
        var gcode: [String] = ["%", "O=PRISM_TOOLPATH"]
        gcode.append("(V-Bit: \(Int(params.vBitAngleDegrees))° · spacing \(String(format: "%.2f", params.spacingMm))mm)")
        if params.spindleRpm > 0 {
            gcode.append("M3 S\(Int(params.spindleRpm))")
        }
        let tanHalf = tan(params.vBitAngleDegrees / 2 * .pi / 180)
        var grooveCount = 0
        var totalLength = 0.0

        for path in paths {
            guard let poly = SpecialtyBoundary.polygonPoints(of: path) else { continue }
            let xs = poly.map { $0.x }
            let ys = poly.map { $0.y }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { continue }
            var y = minY + params.spacingMm / 2
            while y < maxY {
                let runs = SpecialtyBoundary.insideRuns(of: poly, y: y)
                for run in runs {
                    let width = run.x1 - run.x0
                    var depth = min(width, params.spacingMm) / (2 * max(tanHalf, 1e-9))
                    if params.maxDepthMm > 0 {
                        depth = min(depth, params.maxDepthMm)
                    }
                    let z = -(params.startDepthMm + depth)
                    grooveCount += 1
                    totalLength += width
                    gcode.append("")
                    gcode.append("(Groove \(grooveCount): y \(String(format: "%.3f", y)) x \(String(format: "%.3f", run.x0))–\(String(format: "%.3f", run.x1)))")
                    gcode.append("G0 X\(String(format: "%.3f", run.x0)) Y\(String(format: "%.3f", y))")
                    gcode.append("G0 Z\(String(format: "%.1f", params.safeZHeightMm))")
                    gcode.append("G1 Z\(String(format: "%.3f", z)) F\(Int(params.plungeRateMmPerMin))")
                    gcode.append("G1 X\(String(format: "%.3f", run.x1)) F\(Int(params.feedRateMmPerMin))")
                    gcode.append("G0 Z\(String(format: "%.1f", params.safeZHeightMm))")
                }
                y += params.spacingMm
            }
        }
        gcode.append("")
        gcode.append("M30")
        gcode.append("%")
        let time = totalLength / max(params.feedRateMmPerMin, 1) * 60.0 + Double(grooveCount) * 1.5
        return SpecialtyResult(gcodeLines: gcode, estimatedTimeSeconds: time, featureCount: grooveCount)
    }
}

// MARK: - Fluting (F08)

/// Flutes along the SELECTED vectors (the vectors are the flute paths — draw
/// parallel lines for a ribbed board). Open paths cut start→end; closed paths
/// cut around the perimeter. Depth is reached in step-down passes.
public struct FlutingToolpathParams: Codable, Sendable {
    public var startDepthMm: Double
    public var cutDepthMm: Double
    public var passDepthMm: Double      // 0 = single pass to full depth
    public var safeZHeightMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var toolDiameterMm: Double
    public var spindleRpm: Double

    public init(
        startDepthMm: Double = 0,
        cutDepthMm: Double = 4.0,
        passDepthMm: Double = 2.0,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1500,
        plungeRateMmPerMin: Double = 300,
        toolDiameterMm: Double = 6.0,
        spindleRpm: Double = 0
    ) {
        self.startDepthMm = startDepthMm
        self.cutDepthMm = cutDepthMm
        self.passDepthMm = passDepthMm
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.toolDiameterMm = toolDiameterMm
        self.spindleRpm = spindleRpm
    }

    private enum CodingKeys: String, CodingKey {
        case startDepthMm, cutDepthMm, passDepthMm, safeZHeightMm
        case feedRateMmPerMin, plungeRateMmPerMin, toolDiameterMm, spindleRpm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDepthMm = try c.decodeIfPresent(Double.self, forKey: .startDepthMm) ?? 0
        cutDepthMm = try c.decodeIfPresent(Double.self, forKey: .cutDepthMm) ?? 4.0
        passDepthMm = try c.decodeIfPresent(Double.self, forKey: .passDepthMm) ?? 2.0
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1500
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        toolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .toolDiameterMm) ?? 6.0
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startDepthMm, forKey: .startDepthMm)
        try c.encode(cutDepthMm, forKey: .cutDepthMm)
        try c.encode(passDepthMm, forKey: .passDepthMm)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(toolDiameterMm, forKey: .toolDiameterMm)
        try c.encode(spindleRpm, forKey: .spindleRpm)
    }
}

public enum FlutingToolpathEngine {

    public static func compute(
        paths: [VectorPath],
        params: FlutingToolpathParams,
        stockHeightMm: Double = 25.0
    ) -> SpecialtyResult {
        var gcode: [String] = ["%", "O=FLUTING_TOOLPATH"]
        gcode.append("(Tool: \(Int(params.toolDiameterMm * 10))mm · depth \(String(format: "%.2f", params.cutDepthMm))mm)")
        if params.spindleRpm > 0 {
            gcode.append("M3 S\(Int(params.spindleRpm))")
        }
        let passes = params.passDepthMm > 0 ? max(1, Int(ceil(params.cutDepthMm / params.passDepthMm))) : 1
        var fluteCount = 0
        var totalLength = 0.0

        for path in paths {
            guard path.points.count >= 2 else { continue }
            fluteCount += 1
            for p in 1...passes {
                let depth = params.passDepthMm > 0
                    ? min(Double(p) * params.passDepthMm, params.cutDepthMm)
                    : params.cutDepthMm
                let z = -(params.startDepthMm + depth)
                let first = path.points[0]
                gcode.append("")
                gcode.append("(Flute \(fluteCount) pass \(p)/\(passes))")
                gcode.append("G0 X\(String(format: "%.3f", first.x)) Y\(String(format: "%.3f", first.y))")
                gcode.append("G0 Z\(String(format: "%.1f", params.safeZHeightMm))")
                gcode.append("G1 Z\(String(format: "%.3f", z)) F\(Int(params.plungeRateMmPerMin))")
                for point in path.points.dropFirst() {
                    gcode.append("G1 X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y)) F\(Int(params.feedRateMmPerMin))")
                }
                gcode.append("G0 Z\(String(format: "%.1f", params.safeZHeightMm))")
                totalLength += pathLength(path.points)
            }
        }
        gcode.append("")
        gcode.append("M30")
        gcode.append("%")
        let time = totalLength / max(params.feedRateMmPerMin, 1) * 60.0 + Double(fluteCount * passes) * 1.2
        return SpecialtyResult(gcodeLines: gcode, estimatedTimeSeconds: time, featureCount: fluteCount)
    }

    static func pathLength(_ points: [VectorPoint]) -> Double {
        var len = 0.0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            len += (dx * dx + dy * dy).squareRoot()
        }
        return len
    }
}

// MARK: - Chamfer (F11)

/// Bevels the edges of selected vectors with a V-bit: cut ON the vector at
/// depth = chamferWidth / tan(θ/2), so the surface edge of the cut sits
/// exactly `chamferWidth` from the vector line.
public struct ChamferToolpathParams: Codable, Sendable {
    public var chamferWidthMm: Double
    public var vBitAngleDegrees: Double
    public var safeZHeightMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var spindleRpm: Double

    public init(
        chamferWidthMm: Double = 3.0,
        vBitAngleDegrees: Double = 90.0,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1500,
        plungeRateMmPerMin: Double = 300,
        spindleRpm: Double = 0
    ) {
        self.chamferWidthMm = chamferWidthMm
        self.vBitAngleDegrees = vBitAngleDegrees
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.spindleRpm = spindleRpm
    }

    private enum CodingKeys: String, CodingKey {
        case chamferWidthMm, vBitAngleDegrees, safeZHeightMm
        case feedRateMmPerMin, plungeRateMmPerMin, spindleRpm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chamferWidthMm = try c.decodeIfPresent(Double.self, forKey: .chamferWidthMm) ?? 3.0
        vBitAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .vBitAngleDegrees) ?? 90.0
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1500
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chamferWidthMm, forKey: .chamferWidthMm)
        try c.encode(vBitAngleDegrees, forKey: .vBitAngleDegrees)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(spindleRpm, forKey: .spindleRpm)
    }
}

public enum ChamferToolpathEngine {

    public static func compute(
        paths: [VectorPath],
        params: ChamferToolpathParams,
        stockHeightMm: Double = 25.0
    ) -> SpecialtyResult {
        var gcode: [String] = ["%", "O=CHAMFER_TOOLPATH"]
        gcode.append("(V-Bit: \(Int(params.vBitAngleDegrees))° · chamfer \(String(format: "%.2f", params.chamferWidthMm))mm)")
        if params.spindleRpm > 0 {
            gcode.append("M3 S\(Int(params.spindleRpm))")
        }
        let tanHalf = tan(params.vBitAngleDegrees / 2 * .pi / 180)
        let z = -(params.chamferWidthMm / max(tanHalf, 1e-9))
        var edgeCount = 0
        var totalLength = 0.0

        for path in paths {
            guard path.points.count >= 2 else { continue }
            edgeCount += 1
            let first = path.points[0]
            gcode.append("")
            gcode.append("(Edge \(edgeCount))")
            gcode.append("G0 X\(String(format: "%.3f", first.x)) Y\(String(format: "%.3f", first.y))")
            gcode.append("G0 Z\(String(format: "%.1f", params.safeZHeightMm))")
            gcode.append("G1 Z\(String(format: "%.3f", z)) F\(Int(params.plungeRateMmPerMin))")
            for point in path.points.dropFirst() {
                gcode.append("G1 X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y)) F\(Int(params.feedRateMmPerMin))")
            }
            gcode.append("G0 Z\(String(format: "%.1f", params.safeZHeightMm))")
            totalLength += FlutingToolpathEngine.pathLength(path.points)
        }
        gcode.append("")
        gcode.append("M30")
        gcode.append("%")
        let time = totalLength / max(params.feedRateMmPerMin, 1) * 60.0 + Double(edgeCount) * 1.2
        return SpecialtyResult(gcodeLines: gcode, estimatedTimeSeconds: time, featureCount: edgeCount)
    }
}

// MARK: - Quick Engrave (F07)

/// Simple single-pass V-bit engraving along selected vectors — less
/// configurable than V-Carve, built for speed: fixed depth, one pass, follow
/// the vector. The sign-shop "just engrave it" button.
public struct QuickEngraveToolpathParams: Codable, Sendable {
    public var cutDepthMm: Double
    public var vBitAngleDegrees: Double
    public var safeZHeightMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var toolDiameterMm: Double
    public var spindleRpm: Double

    public init(
        cutDepthMm: Double = 1.0,
        vBitAngleDegrees: Double = 90.0,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1500,
        plungeRateMmPerMin: Double = 300,
        toolDiameterMm: Double = 3.0,
        spindleRpm: Double = 0
    ) {
        self.cutDepthMm = cutDepthMm
        self.vBitAngleDegrees = vBitAngleDegrees
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.toolDiameterMm = toolDiameterMm
        self.spindleRpm = spindleRpm
    }

    private enum CodingKeys: String, CodingKey {
        case cutDepthMm, vBitAngleDegrees, safeZHeightMm
        case feedRateMmPerMin, plungeRateMmPerMin, toolDiameterMm, spindleRpm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cutDepthMm = try c.decodeIfPresent(Double.self, forKey: .cutDepthMm) ?? 1.0
        vBitAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .vBitAngleDegrees) ?? 90.0
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1500
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        toolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .toolDiameterMm) ?? 3.0
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cutDepthMm, forKey: .cutDepthMm)
        try c.encode(vBitAngleDegrees, forKey: .vBitAngleDegrees)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(toolDiameterMm, forKey: .toolDiameterMm)
        try c.encode(spindleRpm, forKey: .spindleRpm)
    }
}

public enum QuickEngraveToolpathEngine {

    public static func compute(
        paths: [VectorPath],
        params: QuickEngraveToolpathParams,
        stockHeightMm: Double = 25.0
    ) -> SpecialtyResult {
        var gcode: [String] = ["%", "O=QUICK_ENGRAVE_TOOLPATH"]
        gcode.append("(V-Bit: \(Int(params.vBitAngleDegrees))° · depth \(String(format: "%.2f", params.cutDepthMm))mm)")
        if params.spindleRpm > 0 {
            gcode.append("M3 S\(Int(params.spindleRpm))")
        }
        let z = -params.cutDepthMm
        var featureCount = 0
        var totalLength = 0.0

        for path in paths {
            guard path.points.count >= 2 else { continue }
            featureCount += 1
            let first = path.points[0]
            gcode.append("")
            gcode.append("(Engrave \(featureCount))")
            gcode.append("G0 X\(String(format: "%.3f", first.x)) Y\(String(format: "%.3f", first.y))")
            gcode.append("G0 Z\(String(format: "%.1f", params.safeZHeightMm))")
            gcode.append("G1 Z\(String(format: "%.3f", z)) F\(Int(params.plungeRateMmPerMin))")
            for point in path.points.dropFirst() {
                gcode.append("G1 X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y)) F\(Int(params.feedRateMmPerMin))")
            }
            gcode.append("G0 Z\(String(format: "%.1f", params.safeZHeightMm))")
            totalLength += FlutingToolpathEngine.pathLength(path.points)
        }
        gcode.append("")
        gcode.append("M30")
        gcode.append("%")
        let time = totalLength / max(params.feedRateMmPerMin, 1) * 60.0 + Double(featureCount) * 1.2
        return SpecialtyResult(gcodeLines: gcode, estimatedTimeSeconds: time, featureCount: featureCount)
    }
}

// MARK: - Inlay pocket / plug (F15)

/// V-inlay pair (the classic two-wood inlay). The POCKET (female) is a
/// flat-bottom V-carve of the shape interior (sloped walls from the V-bit,
/// flat floor at `inlayDepthMm`); the PLUG (male) is a profile "on" cut at
/// the same depth so the remaining piece has matching sloped walls.
public struct InlayToolpathParams: Codable, Sendable {
    public enum Variant: String, Codable, Sendable {
        case pocket
        case plug
    }

    public var variant: Variant
    public var inlayDepthMm: Double
    public var vBitAngleDegrees: Double
    public var safeZHeightMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var toolDiameterMm: Double
    public var spindleRpm: Double

    public init(
        variant: Variant = .pocket,
        inlayDepthMm: Double = 6.0,
        vBitAngleDegrees: Double = 90.0,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1200,
        plungeRateMmPerMin: Double = 300,
        toolDiameterMm: Double = 6.0,
        spindleRpm: Double = 0
    ) {
        self.variant = variant
        self.inlayDepthMm = inlayDepthMm
        self.vBitAngleDegrees = vBitAngleDegrees
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.toolDiameterMm = toolDiameterMm
        self.spindleRpm = spindleRpm
    }

    private enum CodingKeys: String, CodingKey {
        case variant, inlayDepthMm, vBitAngleDegrees, safeZHeightMm
        case feedRateMmPerMin, plungeRateMmPerMin, toolDiameterMm, spindleRpm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        variant = try c.decodeIfPresent(Variant.self, forKey: .variant) ?? .pocket
        inlayDepthMm = try c.decodeIfPresent(Double.self, forKey: .inlayDepthMm) ?? 6.0
        vBitAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .vBitAngleDegrees) ?? 90.0
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1200
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        toolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .toolDiameterMm) ?? 6.0
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(variant, forKey: .variant)
        try c.encode(inlayDepthMm, forKey: .inlayDepthMm)
        try c.encode(vBitAngleDegrees, forKey: .vBitAngleDegrees)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(toolDiameterMm, forKey: .toolDiameterMm)
        try c.encode(spindleRpm, forKey: .spindleRpm)
    }
}

public enum InlayToolpathEngine {

    /// Female half: flat-bottom V-carve of the shape interior. Walls slope at
    /// the V-bit angle; the floor sits at −inlayDepth.
    public static func computePocket(
        paths: [VectorPath],
        params: InlayToolpathParams,
        stockHeightMm: Double = 25.0
    ) -> SpecialtyResult {
        let vc = VCarveParams(
            vBitAngleDegrees: params.vBitAngleDegrees,
            feedRateMmPerMin: params.feedRateMmPerMin,
            plungeFeedRateMmPerMin: params.plungeRateMmPerMin,
            maxDepthOfCutMm: params.inlayDepthMm,
            flatBottomMode: true,
            flatDepthMm: params.inlayDepthMm,
            safeZHeightMm: params.safeZHeightMm,
            spindleRpm: params.spindleRpm
        )
        let result = VCarveEngine.compute(vectors: paths, params: vc, stockHeightMm: stockHeightMm)
        return SpecialtyResult(
            gcodeLines: result.gcodeLines,
            estimatedTimeSeconds: result.estimatedTimeSeconds,
            featureCount: paths.count
        )
    }

    /// Male half: profile "on" cut at the inlay depth. The piece INSIDE the
    /// vector keeps its material with V-sloped walls on the outside.
    public static func computePlug(
        paths: [VectorPath],
        params: InlayToolpathParams,
        stockHeightMm: Double = 25.0
    ) -> SpecialtyResult {
        let pp = ProfileToolpathParams(
            cutMode: .onCut,
            feedRateMmPerMin: params.feedRateMmPerMin,
            plungeFeedRateMmPerMin: params.plungeRateMmPerMin,
            maxDepthOfCutMm: params.inlayDepthMm,
            toolDiameterMm: params.toolDiameterMm,
            spindleRpm: params.spindleRpm
        )
        let result = ProfileToolpathEngine.compute(
            vectors: paths, params: pp, material: nil, stockHeightMm: stockHeightMm
        )
        return SpecialtyResult(
            gcodeLines: result.gcodeLines,
            estimatedTimeSeconds: result.estimatedTimeSeconds,
            featureCount: paths.count
        )
    }
}

// MARK: - V-Carve inlay recipe presets (SPK-0802 remainder)

/// A named V-Carve inlay recipe preset: the classic two-wood inlay wants a
/// specific V-bit angle + depth + feeds. Presets map onto the real
/// `InlayToolpathEngine` params so a recipe is just a one-click config.
public struct VCarveInlayRecipe: Codable, Sendable {
    public var name: String
    public var vBitAngleDegrees: Double
    public var inlayDepthMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var toolDiameterMm: Double

    public init(
        name: String,
        vBitAngleDegrees: Double = 90.0,
        inlayDepthMm: Double = 6.0,
        feedRateMmPerMin: Double = 1200,
        plungeRateMmPerMin: Double = 300,
        toolDiameterMm: Double = 6.0
    ) {
        self.name = name
        self.vBitAngleDegrees = vBitAngleDegrees
        self.inlayDepthMm = inlayDepthMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.toolDiameterMm = toolDiameterMm
    }

    /// The four classic V-inlay angles (mirrors the legacy stub's
    /// `InlayEngine.presetRecipes`, now driving the REAL engine).
    public static let presets: [VCarveInlayRecipe] = [
        VCarveInlayRecipe(
            name: "Fine 30° Inlay",
            vBitAngleDegrees: 30, inlayDepthMm: 2.5,
            feedRateMmPerMin: 600, plungeRateMmPerMin: 150, toolDiameterMm: 3.175
        ),
        VCarveInlayRecipe(
            name: "Medium 45° Inlay",
            vBitAngleDegrees: 45, inlayDepthMm: 3.0,
            feedRateMmPerMin: 800, plungeRateMmPerMin: 200, toolDiameterMm: 3.175
        ),
        VCarveInlayRecipe(
            name: "Bold 60° Inlay",
            vBitAngleDegrees: 60, inlayDepthMm: 4.0,
            feedRateMmPerMin: 1000, plungeRateMmPerMin: 300, toolDiameterMm: 6.35
        ),
        VCarveInlayRecipe(
            name: "Deep 90° Inlay",
            vBitAngleDegrees: 90, inlayDepthMm: 5.0,
            feedRateMmPerMin: 1200, plungeRateMmPerMin: 400, toolDiameterMm: 6.35
        ),
    ]

    public static func preset(named name: String) -> VCarveInlayRecipe? {
        presets.first { $0.name == name }
    }

    /// Apply this recipe onto mutable inlay params (variant preserved).
    public func apply(to params: inout InlayToolpathParams) {
        params.vBitAngleDegrees = vBitAngleDegrees
        params.inlayDepthMm = inlayDepthMm
        params.feedRateMmPerMin = feedRateMmPerMin
        params.plungeRateMmPerMin = plungeRateMmPerMin
        params.toolDiameterMm = toolDiameterMm
    }

    /// Materialize full inlay params for a half (pocket/plug).
    public func params(variant: InlayToolpathParams.Variant) -> InlayToolpathParams {
        var p = InlayToolpathParams()
        p.variant = variant
        apply(to: &p)
        return p
    }

    private enum CodingKeys: String, CodingKey {
        case name, vBitAngleDegrees, inlayDepthMm
        case feedRateMmPerMin, plungeRateMmPerMin, toolDiameterMm
    }

    /// Legacy-safe: recipes decoded from partial JSON fall back to the
    /// standard 90° defaults so stored docs stay decodable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Inlay"
        vBitAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .vBitAngleDegrees) ?? 90.0
        inlayDepthMm = try c.decodeIfPresent(Double.self, forKey: .inlayDepthMm) ?? 6.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1200
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        toolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .toolDiameterMm) ?? 6.0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(vBitAngleDegrees, forKey: .vBitAngleDegrees)
        try c.encode(inlayDepthMm, forKey: .inlayDepthMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(toolDiameterMm, forKey: .toolDiameterMm)
    }
}

// MARK: - Drag knife (SPK-0907 remainder)

/// Drag-knife cutting: the blade tip trails the spindle center by
/// `bladeOffsetMm`, so the SPINDLE must travel offset by that distance AHEAD
/// of the tip along the travel direction. At each corner the knife pivots:
/// the tip holds at the corner while the center arcs around it at the blade
/// offset radius — the classic drag-knife toolpath (offset + pivot).
public struct DragKnifeToolpathParams: Codable, Sendable {
    public var bladeOffsetMm: Double
    public var cutDepthMm: Double
    public var pivotThresholdDegrees: Double   // turns below this skip the arc
    public var safeZHeightMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var spindleRpm: Double

    public init(
        bladeOffsetMm: Double = 4.0,
        cutDepthMm: Double = 2.0,
        pivotThresholdDegrees: Double = 0.5,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1200,
        plungeRateMmPerMin: Double = 300,
        spindleRpm: Double = 0
    ) {
        self.bladeOffsetMm = bladeOffsetMm
        self.cutDepthMm = cutDepthMm
        self.pivotThresholdDegrees = pivotThresholdDegrees
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.spindleRpm = spindleRpm
    }

    private enum CodingKeys: String, CodingKey {
        case bladeOffsetMm, cutDepthMm, pivotThresholdDegrees, safeZHeightMm
        case feedRateMmPerMin, plungeRateMmPerMin, spindleRpm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bladeOffsetMm = try c.decodeIfPresent(Double.self, forKey: .bladeOffsetMm) ?? 4.0
        cutDepthMm = try c.decodeIfPresent(Double.self, forKey: .cutDepthMm) ?? 2.0
        pivotThresholdDegrees = try c.decodeIfPresent(Double.self, forKey: .pivotThresholdDegrees) ?? 0.5
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1200
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bladeOffsetMm, forKey: .bladeOffsetMm)
        try c.encode(cutDepthMm, forKey: .cutDepthMm)
        try c.encode(pivotThresholdDegrees, forKey: .pivotThresholdDegrees)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(spindleRpm, forKey: .spindleRpm)
    }
}

public enum DragKnifeToolpathEngine {

    /// Cut each path with the drag-knife offset+pivot model. The emitted
    /// coordinates are SPINDLE CENTER positions; the tip traces the vector.
    /// Returns the same SpecialtyResult shape as the other specialty engines.
    public static func compute(
        paths: [VectorPath],
        params: DragKnifeToolpathParams,
        stockHeightMm: Double = 25.0
    ) -> SpecialtyResult {
        var gcode: [String] = ["%", "O=DRAG_KNIFE_TOOLPATH"]
        gcode.append("(Drag knife: blade offset \(String(format: "%.2f", params.bladeOffsetMm))mm · depth \(String(format: "%.2f", params.cutDepthMm))mm)")
        if params.spindleRpm > 0 {
            gcode.append("M3 S\(Int(params.spindleRpm))")
        }
        let b = max(0.05, params.bladeOffsetMm)
        let threshold = params.pivotThresholdDegrees * .pi / 180
        let z = -params.cutDepthMm
        var featureCount = 0
        var pivotCount = 0
        var totalLength = 0.0

        func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

        for path in paths {
            // Work on the ordered point list (closed paths close the loop).
            var pts = path.points
            guard pts.count >= 2 else { continue }
            let closed = path.isClosed
            if closed, let first = pts.first, pts.last != first {
                pts.append(first)
            }
            featureCount += 1

            // Unit direction of segment i→i+1 (fallback: last known).
            func dir(_ i: Int) -> (Double, Double) {
                let dx = pts[i + 1].x - pts[i].x
                let dy = pts[i + 1].y - pts[i].y
                let len = (dx * dx + dy * dy).squareRoot()
                guard len > 1e-9 else { return (1, 0) }
                return (dx / len, dy / len)
            }

            gcode.append("")
            gcode.append("(Drag knife path \(featureCount))")
            // Start: center = p0 + b·û0 so the tip lands on p0.
            let u0 = dir(0)
            let startX = pts[0].x + b * u0.0
            let startY = pts[0].y + b * u0.1
            gcode.append("G0 X\(fmt(startX)) Y\(fmt(startY))")
            gcode.append("G0 Z\(fmt(params.safeZHeightMm))")
            gcode.append("G1 Z\(fmt(z)) F\(Int(params.plungeRateMmPerMin))")

            var prevU = u0
            for i in 1..<pts.count - 1 {
                let corner = pts[i]
                let nextU = dir(i)
                // Pivot at the corner: center arcs from corner + b·û_prev to
                // corner + b·û_next around the corner point (radius b).
                let sX = corner.x + b * prevU.0
                let sY = corner.y + b * prevU.1
                let eX = corner.x + b * nextU.0
                let eY = corner.y + b * nextU.1
                let cross = prevU.0 * nextU.1 - prevU.1 * nextU.0
                let turn = abs(cross) // |sin θ|
                if turn > sin(threshold) && turn > 1e-9 {
                    // G2 = CW (cross<0), G3 = CCW (cross>0); I/J relative to start.
                    let iJ = corner.x - sX
                    let jJ = corner.y - sY
                    let word = cross > 0 ? "G3" : "G2"
                    gcode.append("G1 X\(fmt(sX)) Y\(fmt(sY)) F\(Int(params.feedRateMmPerMin))")
                    gcode.append("(Pivot \(pivotCount + 1): \(Int(cross > 0 ? 1 : -1) * Int(round(asin(min(1.0, turn)) * 180 / .pi)))° at \(fmt(corner.x)),\(fmt(corner.y)))")
                    gcode.append("\(word) X\(fmt(eX)) Y\(fmt(eY)) I\(fmt(iJ)) J\(fmt(jJ)) F\(Int(params.feedRateMmPerMin))")
                    pivotCount += 1
                    totalLength += b * abs(atan2(nextU.1, nextU.0) - atan2(prevU.1, prevU.0))
                } else {
                    // Small turn: straight reposition (arc radius ≈ chord).
                    gcode.append("G1 X\(fmt(eX)) Y\(fmt(eY)) F\(Int(params.feedRateMmPerMin))")
                }
                prevU = nextU
            }
            // Final segment: center arrives at p_last + b·û_last (tip on last point).
            let lastU = dir(pts.count - 2)
            let endX = pts[pts.count - 1].x + b * lastU.0
            let endY = pts[pts.count - 1].y + b * lastU.1
            gcode.append("G1 X\(fmt(endX)) Y\(fmt(endY)) F\(Int(params.feedRateMmPerMin))")
            // Closed path: the corner at the closing point (p_last == p_0) also
            // pivots — from the last segment's direction back to the first.
            if closed, pts.count > 2 {
                let corner = pts[pts.count - 1]
                let sX = corner.x + b * lastU.0
                let sY = corner.y + b * lastU.1
                let eX = corner.x + b * u0.0
                let eY = corner.y + b * u0.1
                let cross = lastU.0 * u0.1 - lastU.1 * u0.0
                let turn = abs(cross)
                if turn > sin(threshold) && turn > 1e-9 {
                    let iJ = corner.x - sX
                    let jJ = corner.y - sY
                    let word = cross > 0 ? "G3" : "G2"
                    gcode.append("G1 X\(fmt(sX)) Y\(fmt(sY)) F\(Int(params.feedRateMmPerMin))")
                    gcode.append("(Pivot \(pivotCount + 1): \(Int(cross > 0 ? 1 : -1) * Int(round(asin(min(1.0, turn)) * 180 / .pi)))° at \(fmt(corner.x)),\(fmt(corner.y)))")
                    gcode.append("\(word) X\(fmt(eX)) Y\(fmt(eY)) I\(fmt(iJ)) J\(fmt(jJ)) F\(Int(params.feedRateMmPerMin))")
                    pivotCount += 1
                } else {
                    gcode.append("G1 X\(fmt(eX)) Y\(fmt(eY)) F\(Int(params.feedRateMmPerMin))")
                }
            }
            gcode.append("G0 Z\(fmt(params.safeZHeightMm))")
            totalLength += FlutingToolpathEngine.pathLength(pts)
        }
        gcode.append("")
        gcode.append("M30")
        gcode.append("%")
        let time = totalLength / max(params.feedRateMmPerMin, 1) * 60.0 + Double(featureCount + pivotCount) * 1.2
        return SpecialtyResult(gcodeLines: gcode, estimatedTimeSeconds: time, featureCount: featureCount)
    }
}

// MARK: - Texture (SPK-0900 remainder)

/// Decorative area texture: parallel or crosshatch grooves clipped inside the
/// selected closed vectors. V-groove depth derives from spacing (like Prism);
/// flat mode cuts a constant depth with a straight tool.
public struct TextureToolpathParams: Codable, Sendable {
    public enum Pattern: String, Codable, Sendable {
        case parallel
        case crosshatch
    }

    public var pattern: Pattern
    public var spacingMm: Double
    public var angleDegrees: Double       // 0 = grooves along X
    public var cutStyle: TextureCutStyle  // vGroove (default) or flat
    public var vBitAngleDegrees: Double
    public var flatDepthMm: Double
    public var maxDepthMm: Double
    public var safeZHeightMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var spindleRpm: Double

    public enum TextureCutStyle: String, Codable, Sendable {
        case vGroove
        case flat
    }

    public init(
        pattern: Pattern = .parallel,
        spacingMm: Double = 6.0,
        angleDegrees: Double = 0,
        cutStyle: TextureCutStyle = .vGroove,
        vBitAngleDegrees: Double = 90.0,
        flatDepthMm: Double = 2.0,
        maxDepthMm: Double = 0,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1500,
        plungeRateMmPerMin: Double = 300,
        spindleRpm: Double = 0
    ) {
        self.pattern = pattern
        self.spacingMm = spacingMm
        self.angleDegrees = angleDegrees
        self.cutStyle = cutStyle
        self.vBitAngleDegrees = vBitAngleDegrees
        self.flatDepthMm = flatDepthMm
        self.maxDepthMm = maxDepthMm
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.spindleRpm = spindleRpm
    }

    private enum CodingKeys: String, CodingKey {
        case pattern, spacingMm, angleDegrees, cutStyle, vBitAngleDegrees
        case flatDepthMm, maxDepthMm, safeZHeightMm
        case feedRateMmPerMin, plungeRateMmPerMin, spindleRpm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pattern = try c.decodeIfPresent(Pattern.self, forKey: .pattern) ?? .parallel
        spacingMm = try c.decodeIfPresent(Double.self, forKey: .spacingMm) ?? 6.0
        angleDegrees = try c.decodeIfPresent(Double.self, forKey: .angleDegrees) ?? 0
        cutStyle = try c.decodeIfPresent(TextureCutStyle.self, forKey: .cutStyle) ?? .vGroove
        vBitAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .vBitAngleDegrees) ?? 90.0
        flatDepthMm = try c.decodeIfPresent(Double.self, forKey: .flatDepthMm) ?? 2.0
        maxDepthMm = try c.decodeIfPresent(Double.self, forKey: .maxDepthMm) ?? 0
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1500
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pattern, forKey: .pattern)
        try c.encode(spacingMm, forKey: .spacingMm)
        try c.encode(angleDegrees, forKey: .angleDegrees)
        try c.encode(cutStyle, forKey: .cutStyle)
        try c.encode(vBitAngleDegrees, forKey: .vBitAngleDegrees)
        try c.encode(flatDepthMm, forKey: .flatDepthMm)
        try c.encode(maxDepthMm, forKey: .maxDepthMm)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(spindleRpm, forKey: .spindleRpm)
    }
}

public enum TextureToolpathEngine {

    /// Raster the pattern inside each closed boundary. Grooves run at
    /// `angleDegrees` (and +90° for crosshatch); V-groove depth =
    /// min(runWidth, spacing) / (2·tan(θ/2)) so grooves meet at the bottom.
    public static func compute(
        paths: [VectorPath],
        params: TextureToolpathParams,
        stockHeightMm: Double = 25.0
    ) -> SpecialtyResult {
        var gcode: [String] = ["%", "O=TEXTURE_TOOLPATH"]
        gcode.append("(Texture: \(params.pattern == .crosshatch ? "crosshatch" : "parallel") · spacing \(String(format: "%.2f", params.spacingMm))mm · \(Int(params.angleDegrees))°)")
        if params.spindleRpm > 0 {
            gcode.append("M3 S\(Int(params.spindleRpm))")
        }
        let tanHalf = tan(params.vBitAngleDegrees / 2 * .pi / 180)
        let spacing = max(0.1, params.spacingMm)
        var grooveCount = 0
        var totalLength = 0.0

        func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

        // Groove passes: parallel = one direction; crosshatch = θ and θ+90°.
        let angles: [Double] = params.pattern == .crosshatch
            ? [params.angleDegrees, params.angleDegrees + 90]
            : [params.angleDegrees]

        for path in paths {
            guard let poly = SpecialtyBoundary.polygonPoints(of: path) else { continue }
            for angle in angles {
                // Rotate the polygon so grooves are horizontal (X-aligned),
                // scanline at constant y, then rotate endpoints back.
                let rad = -angle * .pi / 180
                let cosA = cos(rad), sinA = sin(rad)
                let rotated = poly.map { p -> VectorPoint in
                    VectorPoint(x: p.x * cosA - p.y * sinA, y: p.x * sinA + p.y * cosA)
                }
                let ys = rotated.map { $0.y }
                guard let minY = ys.min(), let maxY = ys.max() else { continue }
                var y = minY + spacing / 2
                while y < maxY {
                    let runs = SpecialtyBoundary.insideRuns(of: rotated, y: y)
                    for run in runs {
                        let width = run.x1 - run.x0
                        let depth: Double
                        if params.cutStyle == .vGroove {
                            var d = min(width, spacing) / (2 * max(tanHalf, 1e-9))
                            if params.maxDepthMm > 0 { d = min(d, params.maxDepthMm) }
                            depth = d
                        } else {
                            depth = params.flatDepthMm
                        }
                        let z = -depth
                        // Rotate endpoints back to world space (scanline y
                        // is the run's constant y).
                        let ax = run.x0 * cosA + y * sinA
                        let ay = -run.x0 * sinA + y * cosA
                        let bx = run.x1 * cosA + y * sinA
                        let by = -run.x1 * sinA + y * cosA
                        grooveCount += 1
                        totalLength += width
                        gcode.append("")
                        gcode.append("(Texture groove \(grooveCount))")
                        gcode.append("G0 X\(fmt(ax)) Y\(fmt(ay))")
                        gcode.append("G0 Z\(fmt(params.safeZHeightMm))")
                        gcode.append("G1 Z\(fmt(z)) F\(Int(params.plungeRateMmPerMin))")
                        gcode.append("G1 X\(fmt(bx)) Y\(fmt(by)) F\(Int(params.feedRateMmPerMin))")
                        gcode.append("G0 Z\(fmt(params.safeZHeightMm))")
                    }
                    y += spacing
                }
            }
        }
        gcode.append("")
        gcode.append("M30")
        gcode.append("%")
        let time = totalLength / max(params.feedRateMmPerMin, 1) * 60.0 + Double(grooveCount) * 1.5
        return SpecialtyResult(gcodeLines: gcode, estimatedTimeSeconds: time, featureCount: grooveCount)
    }
}

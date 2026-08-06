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

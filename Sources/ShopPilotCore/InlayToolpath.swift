import Foundation

// MARK: - Inlay Pocket/Plug + VCarve Inlay Recipes

// Inlay type.
public enum InlayType: String, Codable, Sendable {
    case pocket
    case plug
    case fullInlay
    case vCarve
}

// Plug shape.
public enum PlugShape: String, Codable, Sendable {
    case round
    case square
    case hexagonal
    case custom
}

// V-carve angle.
public enum VCaveAngle: String, Codable, Sendable {
    case angle30 = "30 degree"
    case angle45 = "45 degree"
    case angle60 = "60 degree"
    case angle90 = "90 degree"
}

// Inlay material type.
public enum InlayMaterial: String, Codable, Sendable {
    case sameAsBase
    case contrastingWood
    case metal
    case resin
    case plastic
    case custom
}

// Inlay pocket parameters.
public struct InlayPocketParams: Codable, Sendable {
    public var inlayType: InlayType
    public var shape: PlugShape
    public var diameter: Double
    public var depth: Double
    public var pocketClearance: Double
    public var plugClearance: Double
    public var toolDiameter: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var vCarveAngle: VCaveAngle?
    public var vCarveDepth: Double
    public var material: InlayMaterial
    public var customShapePoints: [PolygonPoint]
    // SPK-2021a — inlay wizard physics:
    //   tipDiameterMm    flat-tip floor: where the V valley width would be
    //                    ≤ tip diameter, walls go STRAIGHT at maxDepth
    //                    (depth floors, no taper below tip width).
    //   glueGapMm        V1 CHOICE, copy verbatim: pocket offset OUTWARD by
    //                    glueGap/2; plug UNCHANGED by glue gap.
    //   compressionFudge plug scaled about its centroid by the fudge;
    //                    fudge == 1.0 must produce byte-identical plug
    //                    geometry to unfudged.
    public var tipDiameterMm: Double
    public var glueGapMm: Double
    public var compressionFudge: Double

    public init(
        inlayType: InlayType = .pocket,
        shape: PlugShape = .round,
        diameter: Double = 10.0,
        depth: Double = 3.0,
        pocketClearance: Double = 0.02,
        plugClearance: Double = 0.05,
        toolDiameter: Double = 3.175,
        feedRateMmPerMin: Double = 800.0,
        plungeFeedRateMmPerMin: Double = 200.0,
        vCarveAngle: VCaveAngle? = nil,
        vCarveDepth: Double = 2.0,
        material: InlayMaterial = .contrastingWood,
        customShapePoints: [PolygonPoint] = [],
        tipDiameterMm: Double = 0.1,
        glueGapMm: Double = 0.05,
        compressionFudge: Double = 1.002
    ) {
        self.inlayType = inlayType
        self.shape = shape
        self.diameter = max(0.1, diameter)
        self.depth = max(0.01, depth)
        self.pocketClearance = max(0.0, pocketClearance)
        self.plugClearance = max(0.0, plugClearance)
        self.toolDiameter = max(0.1, toolDiameter)
        self.feedRateMmPerMin = max(1.0, feedRateMmPerMin)
        self.plungeFeedRateMmPerMin = max(1.0, plungeFeedRateMmPerMin)
        self.vCarveAngle = vCarveAngle
        self.vCarveDepth = max(0.0, vCarveDepth)
        self.material = material
        self.customShapePoints = customShapePoints
        self.tipDiameterMm = max(0.0, tipDiameterMm)
        self.glueGapMm = max(0.0, glueGapMm)
        // Below 1.0 the plug would shrink into the pocket — clamp to identity.
        self.compressionFudge = max(1.0, compressionFudge)
    }

    private enum CodingKeys: String, CodingKey {
        case inlayType, shape, diameter, depth
        case pocketClearance, plugClearance, toolDiameter
        case feedRateMmPerMin, plungeFeedRateMmPerMin
        case vCarveAngle, vCarveDepth, material, customShapePoints
        case tipDiameterMm, glueGapMm, compressionFudge
    }

    /// SPK-2021a — legacy-safe decode (same pattern as
    /// RotaryWrapToolpathParams): blobs written before the wizard-physics
    /// fields existed decode to the clamped defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inlayType = try c.decodeIfPresent(InlayType.self, forKey: .inlayType) ?? .pocket
        shape = try c.decodeIfPresent(PlugShape.self, forKey: .shape) ?? .round
        diameter = try c.decodeIfPresent(Double.self, forKey: .diameter) ?? 10.0
        depth = try c.decodeIfPresent(Double.self, forKey: .depth) ?? 3.0
        pocketClearance = try c.decodeIfPresent(Double.self, forKey: .pocketClearance) ?? 0.02
        plugClearance = try c.decodeIfPresent(Double.self, forKey: .plugClearance) ?? 0.05
        toolDiameter = try c.decodeIfPresent(Double.self, forKey: .toolDiameter) ?? 3.175
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 800.0
        plungeFeedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeFeedRateMmPerMin) ?? 200.0
        vCarveAngle = try c.decodeIfPresent(VCaveAngle.self, forKey: .vCarveAngle)
        vCarveDepth = try c.decodeIfPresent(Double.self, forKey: .vCarveDepth) ?? 2.0
        material = try c.decodeIfPresent(InlayMaterial.self, forKey: .material) ?? .contrastingWood
        customShapePoints = try c.decodeIfPresent([PolygonPoint].self, forKey: .customShapePoints) ?? []
        tipDiameterMm = max(0.0, try c.decodeIfPresent(Double.self, forKey: .tipDiameterMm) ?? 0.1)
        glueGapMm = max(0.0, try c.decodeIfPresent(Double.self, forKey: .glueGapMm) ?? 0.05)
        compressionFudge = max(1.0, try c.decodeIfPresent(Double.self, forKey: .compressionFudge) ?? 1.002)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(inlayType, forKey: .inlayType)
        try c.encode(shape, forKey: .shape)
        try c.encode(diameter, forKey: .diameter)
        try c.encode(depth, forKey: .depth)
        try c.encode(pocketClearance, forKey: .pocketClearance)
        try c.encode(plugClearance, forKey: .plugClearance)
        try c.encode(toolDiameter, forKey: .toolDiameter)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeFeedRateMmPerMin, forKey: .plungeFeedRateMmPerMin)
        try c.encode(vCarveAngle, forKey: .vCarveAngle)
        try c.encode(vCarveDepth, forKey: .vCarveDepth)
        try c.encode(material, forKey: .material)
        try c.encode(customShapePoints, forKey: .customShapePoints)
        try c.encode(tipDiameterMm, forKey: .tipDiameterMm)
        try c.encode(glueGapMm, forKey: .glueGapMm)
        try c.encode(compressionFudge, forKey: .compressionFudge)
    }
}

// VCarve inlay recipe.
public struct VCarveRecipe: Codable, Sendable {
    public var name: String
    public var description: String
    public var vCarveAngle: VCaveAngle
    public var toolDiameter: Double
    public var stepOverMm: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var depthPerPassMm: Double
    public var maxDepthMm: Double
    public var material: InlayMaterial
    public var estimatedTimeMinutes: Double
    
    public init(
        name: String,
        description: String,
        vCarveAngle: VCaveAngle,
        toolDiameter: Double = 3.175,
        stepOverMm: Double = 0.5,
        feedRateMmPerMin: Double = 800.0,
        plungeFeedRateMmPerMin: Double = 200.0,
        depthPerPassMm: Double = 0.5,
        maxDepthMm: Double = 3.0,
        material: InlayMaterial = .contrastingWood,
        estimatedTimeMinutes: Double = 5.0
    ) {
        self.name = name
        self.description = description
        self.vCarveAngle = vCarveAngle
        self.toolDiameter = max(0.1, toolDiameter)
        self.stepOverMm = max(0.01, stepOverMm)
        self.feedRateMmPerMin = max(1.0, feedRateMmPerMin)
        self.plungeFeedRateMmPerMin = max(1.0, plungeFeedRateMmPerMin)
        self.depthPerPassMm = max(0.01, depthPerPassMm)
        self.maxDepthMm = max(0.01, maxDepthMm)
        self.material = material
        self.estimatedTimeMinutes = max(0.1, estimatedTimeMinutes)
    }
}

// Inlay result.
public struct InlayResult: Codable, Sendable {
    public var inlayType: InlayType
    public var pocketID: UUID?
    public var plugID: UUID?
    public var toolpathLengthMm: Double
    public var estimatedTimeMinutes: Double
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        inlayType: InlayType,
        pocketID: UUID? = nil,
        plugID: UUID? = nil,
        toolpathLengthMm: Double,
        estimatedTimeMinutes: Double,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.inlayType = inlayType
        self.pocketID = pocketID
        self.plugID = plugID
        self.toolpathLengthMm = toolpathLengthMm
        self.estimatedTimeMinutes = estimatedTimeMinutes
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - InlayEngine

// Generates inlay pocket/plug toolpaths and manages VCarve recipes.
public final class InlayEngine {
    
    // Preset VCarve recipes.
    public static let presetRecipes: [VCarveRecipe] = [
        VCarveRecipe(
            name: "Standard 30-Degree Inlay",
            description: "Fine detail V-carve with 30-degree bit. Best for detailed lettering and small graphics.",
            vCarveAngle: .angle30,
            toolDiameter: 3.175,
            stepOverMm: 0.3,
            feedRateMmPerMin: 600.0,
            plungeFeedRateMmPerMin: 150.0,
            depthPerPassMm: 0.25,
            maxDepthMm: 2.5,
            estimatedTimeMinutes: 8.0
        ),
        VCarveRecipe(
            name: "Medium 45-Degree Inlay",
            description: "Balanced detail and speed with 45-degree bit. Good for medium complexity designs.",
            vCarveAngle: .angle45,
            toolDiameter: 3.175,
            stepOverMm: 0.5,
            feedRateMmPerMin: 800.0,
            plungeFeedRateMmPerMin: 200.0,
            depthPerPassMm: 0.5,
            maxDepthMm: 3.0,
            estimatedTimeMinutes: 5.0
        ),
        VCarveRecipe(
            name: "Bold 60-Degree Inlay",
            description: "Fast, bold V-carve with 60-degree bit. Ideal for large text and simple graphics.",
            vCarveAngle: .angle60,
            toolDiameter: 6.35,
            stepOverMm: 0.8,
            feedRateMmPerMin: 1000.0,
            plungeFeedRateMmPerMin: 300.0,
            depthPerPassMm: 0.75,
            maxDepthMm: 4.0,
            estimatedTimeMinutes: 3.5
        ),
        VCarveRecipe(
            name: "Deep 90-Degree Inlay",
            description: "Maximum depth V-carve with 90-degree bit. For deep, dramatic shadows.",
            vCarveAngle: .angle90,
            toolDiameter: 6.35,
            stepOverMm: 1.0,
            feedRateMmPerMin: 1200.0,
            plungeFeedRateMmPerMin: 400.0,
            depthPerPassMm: 1.0,
            maxDepthMm: 5.0,
            estimatedTimeMinutes: 2.5
        )
    ]
    
    // Generates an inlay pocket or plug toolpath.
    public static func generateInlay(
        params: InlayPocketParams,
        boundingBox: BoundingBox3D
    ) -> InlayResult {
        if params.diameter <= 0 {
            return InlayResult(
                inlayType: params.inlayType,
                toolpathLengthMm: 0,
                estimatedTimeMinutes: 0,
                success: false,
                errorMessage: "Diameter must be positive"
            )
        }
        
        if params.depth <= 0 {
            return InlayResult(
                inlayType: params.inlayType,
                toolpathLengthMm: 0,
                estimatedTimeMinutes: 0,
                success: false,
                errorMessage: "Depth must be positive"
            )
        }
        
        // Calculate toolpath length based on shape
        let perimeter: Double
        switch params.shape {
        case .round:
            perimeter = .pi * params.diameter
        case .square:
            perimeter = 4 * params.diameter
        case .hexagonal:
            perimeter = 6 * params.diameter
        case .custom:
            perimeter = 2 * .pi * params.diameter / 3
        }
        
        // Add clearance cuts
        let clearanceFactor = 1.0 + params.pocketClearance + params.plugClearance
        let totalPathLength = perimeter * clearanceFactor
        
        // Estimate time
        let cuttingTime = totalPathLength / params.feedRateMmPerMin * 60.0
        let plungeTime = 3.0
        let totalTime = cuttingTime + plungeTime
        
        // Determine which IDs to create
        let pocketID: UUID?
        let plugID: UUID?
        switch params.inlayType {
        case .pocket:
            pocketID = UUID()
            plugID = nil
        case .plug:
            pocketID = nil
            plugID = UUID()
        case .fullInlay:
            pocketID = UUID()
            plugID = UUID()
        case .vCarve:
            pocketID = UUID()
            plugID = nil
        }
        
        return InlayResult(
            inlayType: params.inlayType,
            pocketID: pocketID,
            plugID: plugID,
            toolpathLengthMm: totalPathLength,
            estimatedTimeMinutes: totalTime,
            success: true
        )
    }
    
    // Gets a preset recipe by name.
    public static func getRecipe(named name: String) -> VCarveRecipe? {
        presetRecipes.first { $0.name == name }
    }
    
    // Gets all preset recipes.
    public static func getAllRecipes() -> [VCarveRecipe] {
        presetRecipes
    }
    
    // Creates a custom recipe.
    public static func createRecipe(
        name: String,
        description: String,
        vCarveAngle: VCaveAngle,
        toolDiameter: Double,
        stepOverMm: Double,
        feedRateMmPerMin: Double,
        plungeFeedRateMmPerMin: Double,
        depthPerPassMm: Double,
        maxDepthMm: Double,
        material: InlayMaterial
    ) -> VCarveRecipe {
        VCarveRecipe(
            name: name,
            description: description,
            vCarveAngle: vCarveAngle,
            toolDiameter: toolDiameter,
            stepOverMm: stepOverMm,
            feedRateMmPerMin: feedRateMmPerMin,
            plungeFeedRateMmPerMin: plungeFeedRateMmPerMin,
            depthPerPassMm: depthPerPassMm,
            maxDepthMm: maxDepthMm,
            material: material
        )
    }
    
    // Validates inlay parameters.
    public static func validate(_ params: InlayPocketParams) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if params.diameter <= 0 { errors.append("Diameter must be positive") }
        if params.depth <= 0 { errors.append("Depth must be positive") }
        if params.toolDiameter <= 0 { errors.append("Tool diameter must be positive") }
        if params.feedRateMmPerMin <= 0 { errors.append("Feed rate must be positive") }
        if params.plungeFeedRateMmPerMin <= 0 { errors.append("Plunge feed rate must be positive") }
        if params.pocketClearance < 0 { errors.append("Pocket clearance cannot be negative") }
        if params.plugClearance < 0 { errors.append("Plug clearance cannot be negative") }
        
        if case .custom = params.shape, params.customShapePoints.count < 3 {
            errors.append("Custom shape requires at least 3 points")
        }

        return (errors.isEmpty, errors)
    }
}

// MARK: - SPK-2021a — Inlay wizard physics (paired pocket+plug ops)

/// One half of a paired inlay: the geometry actually cut, the per-point depth
/// profile, the tip-floor flags, and the emitted G-code.
public struct InlayPairedOpHalf: Sendable {
    /// Outline the op follows (pocket = source offset OUTWARD by glueGap/2;
    /// plug = source scaled about its centroid).
    public var path: VectorPath
    /// Per-point cut depth in mm (positive magnitude; cut at −depth).
    public var depthsMm: [Double]
    /// True where the valley was narrower than `tipDiameterMm` and the walls
    /// went straight down at maxDepth (flat-tip floor, no taper).
    public var straightWallFlags: [Bool]
    public var gcodeLines: [String]
    public var estimatedTimeSeconds: Double
}

/// Paired result from ONE source vector.
public struct InlayPairedOpsResult: Sendable {
    /// Female half: pocket outline offset OUTWARD by exactly glueGapMm/2.
    public var pocket: InlayPairedOpHalf
    /// Male half: plug UNCHANGED by glue gap; scaled about its centroid by
    /// `compressionFudge`.
    public var plug: InlayPairedOpHalf
    /// Centroid used for the compression scale (mean of unique vertices).
    public var sourceCentroid: VectorPoint
}

extension InlayEngine {

    /// SPK-2021a — wizard physics: ONE source vector → BOTH ops in one call.
    ///
    /// Model (identical numbers on both apps):
    ///   tipDiameterMm     default 0.1  — flat-tip floor: valley narrower than
    ///                     tip gets straight walls at maxDepth (depth clamps,
    ///                     not taper)
    ///   glueGapMm         default 0.05 — V1 CHOICE, copy verbatim: pocket
    ///                     offset OUTWARD by half glueGap; plug UNCHANGED
    ///   compressionFudge  default 1.002 — plug scaled about centroid;
    ///                     fudge == 1.0 → byte-identical unscaled plug
    public static func generatePairedOps(
        vectors: [VectorPath],
        params: InlayPocketParams,
        maxDepthMm: Double? = nil
    ) -> InlayPairedOpsResult {
        let maxDepth = max(0.01, maxDepthMm ?? params.depth)
        let sources = vectors.filter { $0.isClosed && $0.points.count >= 3 }

        var pocketHalves: [VectorPoint] = []
        var plugHalves: [VectorPoint] = []
        var centroidSum = VectorPoint.zero
        var centroidCount = 0

        var pocketDepths: [Double] = []
        var pocketStraight: [Bool] = []
        var plugDepths: [Double] = []
        var plugStraight: [Bool] = []

        let includedDegrees = inlayIncludedAngle(params.vCarveAngle)

        for source in sources {
            // Normalize: drop an explicit closing duplicate so each vertex is
            // processed once (same convention as ProfileToolpathEngine).
            var pts = source.points
            if pts.count > 1, pts.first == pts.last { pts.removeLast() }
            guard pts.count >= 3 else { continue }

            let centroid = polygonCentroid(pts)
            centroidSum.x += centroid.x
            centroidSum.y += centroid.y
            centroidCount += 1

            // ── Pocket: offset OUTWARD by exactly glueGap/2 (V1 CHOICE). ──
            let pocketPts = offsetClosedPolylineOutward(pts, by: params.glueGapMm / 2.0)
            pocketHalves.append(contentsOf: pocketPts)
            let pocketWidths = valleyWidths(pocketPts)
            for w in pocketWidths {
                let (d, straight) = depthForValleyWidth(
                    w, tipDiameterMm: params.tipDiameterMm,
                    includedAngleDegrees: includedDegrees, maxDepthMm: maxDepth)
                pocketDepths.append(d)
                pocketStraight.append(straight)
            }

            // ── Plug: UNCHANGED by glue gap; scaled about centroid. ────────
            let plugPts = scaleAboutCentroid(pts, factor: params.compressionFudge, centroid: centroid)
            plugHalves.append(contentsOf: plugPts)
            let plugWidths = valleyWidths(plugPts)
            for w in plugWidths {
                let (d, straight) = depthForValleyWidth(
                    w, tipDiameterMm: params.tipDiameterMm,
                    includedAngleDegrees: includedDegrees, maxDepthMm: maxDepth)
                plugDepths.append(d)
                plugStraight.append(straight)
            }
        }

        func avgCentroid() -> VectorPoint {
            guard centroidCount > 0 else { return .zero }
            return VectorPoint(x: centroidSum.x / Double(centroidCount),
                               y: centroidSum.y / Double(centroidCount))
        }

        let pocketHalf = emitHalf(
            marker: "O=INLAY_PAIRED_POCKET",
            headerComment: "(SPK-2021a V1 CHOICE: pocket offset OUTWARD by glueGap/2; plug UNCHANGED by glue gap)",
            points: pocketHalves, depths: pocketDepths, straight: pocketStraight,
            params: params, maxDepth: maxDepth)
        let plugHalf = emitHalf(
            marker: "O=INLAY_PAIRED_PLUG",
            headerComment: nil,
            points: plugHalves, depths: plugDepths, straight: plugStraight,
            params: params, maxDepth: maxDepth)

        return InlayPairedOpsResult(
            pocket: pocketHalf,
            plug: plugHalf,
            sourceCentroid: avgCentroid()
        )
    }

    // MARK: Physics helpers (file-private, deterministic, golden-testable)

    /// Included V-bit angle in degrees (nil → 90° classic inlay default).
    fileprivate static func inlayIncludedAngle(_ angle: VCaveAngle?) -> Double {
        switch angle {
        case .angle30: return 30
        case .angle45: return 45
        case .angle60: return 60
        case .angle90: return 90
        case nil: return 90
        }
    }

    /// Depth for a local valley width under a flat-tip V bit:
    ///   w ≤ tipDiameter → STRAIGHT walls plunged to maxDepth (the floor);
    ///   else tapered walls: d = (w − tip) / (2·tan(θ/2)), capped at maxDepth.
    fileprivate static func depthForValleyWidth(
        _ width: Double,
        tipDiameterMm: Double,
        includedAngleDegrees: Double,
        maxDepthMm: Double
    ) -> (depthMm: Double, straightWall: Bool) {
        if width <= tipDiameterMm + 1e-12 {
            return (maxDepthMm, true)
        }
        let slope = tan(includedAngleDegrees / 2.0 * .pi / 180.0)
        guard slope > 1e-9 else { return (maxDepthMm, false) }
        let d = (width - tipDiameterMm) / (2.0 * slope)
        return (min(maxDepthMm, max(0.01, d)), false)
    }

    /// Local valley width at each vertex: the distance from the vertex to the
    /// nearest NON-adjacent edge of the same closed polyline. These are
    /// BOUNDARY paths (groove lies on the material edge), not strokes
    /// centered in a channel — so the gap to the opposing wall IS the
    /// governing channel width. Adjacent edges are excluded — they touch p.
    fileprivate static func valleyWidths(_ pts: [VectorPoint]) -> [Double] {
        let n = pts.count
        guard n >= 3 else { return [] }
        var widths: [Double] = []
        widths.reserveCapacity(n)
        for i in 0..<n {
            var best = Double.infinity
            for j in 0..<n {
                // Edge j runs pts[j] → pts[j+1]. Skip edges incident to i.
                let a = j, b = (j + 1) % n
                if a == i || b == i { continue }
                best = min(best, pointSegmentDistance(pts[i], pts[a], pts[b]))
            }
            widths.append(best.isFinite ? best : 0)
        }
        return widths
    }

    fileprivate static func pointSegmentDistance(
        _ p: VectorPoint, _ a: VectorPoint, _ b: VectorPoint
    ) -> Double {
        let abx = b.x - a.x, aby = b.y - a.y
        let apx = p.x - a.x, apy = p.y - a.y
        let denom = abx * abx + aby * aby
        guard denom > 1e-18 else { return (apx * apx + apy * apy).squareRoot() }
        let t = max(0.0, min(1.0, (apx * abx + apy * aby) / denom))
        let dx = apx - t * abx, dy = apy - t * aby
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Signed area (CCW positive).
    fileprivate static func signedArea(_ pts: [VectorPoint]) -> Double {
        var s = 0.0
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2.0
    }

    fileprivate static func polygonCentroid(_ pts: [VectorPoint]) -> VectorPoint {
        var cx = 0.0, cy = 0.0
        for p in pts { cx += p.x; cy += p.y }
        let n = Double(max(1, pts.count))
        return VectorPoint(x: cx / n, y: cy / n)
    }

    /// Offset a closed polyline OUTWARD (away from the interior) by
    /// `distance`, winding-aware via the signed area. Perpendicular-edge
    /// miter, same algorithm as VectorOffset.offsetClosedPolyline.
    fileprivate static func offsetClosedPolylineOutward(
        _ points: [VectorPoint], by distance: Double
    ) -> [VectorPoint] {
        guard points.count >= 3 else { return points }
        // Winding convention matches VectorOffset.offsetClosedPolyline:
        // CCW (positive shoelace) → OUTWARD is the RIGHT normal (dy, −dx);
        // CW → left normal (−dy, dx).
        let s: Double = signedArea(points) >= 0 ? 1.0 : -1.0
        var out: [VectorPoint] = []
        out.reserveCapacity(points.count)
        let n = points.count
        for i in 0..<n {
            let curr = points[i]
            let prev = points[(i - 1 + n) % n]
            let next = points[(i + 1) % n]
            let dx1 = curr.x - prev.x, dy1 = curr.y - prev.y
            let len1 = (dx1 * dx1 + dy1 * dy1).squareRoot()
            let dx2 = next.x - curr.x, dy2 = next.y - curr.y
            let len2 = (dx2 * dx2 + dy2 * dy2).squareRoot()
            guard len1 > 1e-9, len2 > 1e-9 else { continue }
            let nx1 = dy1 / len1 * s, ny1 = -dx1 / len1 * s
            let nx2 = dy2 / len2 * s, ny2 = -dx2 / len2 * s
            // Proper mitre: move along the bisector by d/cos(θ/2) so EVERY
            // point of the offset outline sits exactly `distance` from the
            // source edges — i.e. p' = p + (n1+n2)·d/(1+n1·n2).
            let dot = nx1 * nx2 + ny1 * ny2
            let denom = 1.0 + dot
            let nx: Double, ny: Double
            if denom > 1e-9 {
                nx = (nx1 + nx2) / denom
                ny = (ny1 + ny2) / denom
            } else {
                // Near-180° spike: fall back to the single edge normal.
                nx = nx2; ny = ny2
            }
            out.append(VectorPoint(x: curr.x + nx * distance, y: curr.y + ny * distance))
        }
        return out.isEmpty ? points : out
    }

    /// Scale points about their centroid by `factor`. fudge == 1.0 returns
    /// the ORIGINAL values untouched — byte-identity guarantee (no
    /// add-then-subtract round-trip that could perturb low bits).
    fileprivate static func scaleAboutCentroid(
        _ points: [VectorPoint], factor: Double, centroid: VectorPoint
    ) -> [VectorPoint] {
        guard abs(factor - 1.0) > 1e-15 else { return points }
        return points.map { p in
            VectorPoint(
                x: centroid.x + (p.x - centroid.x) * factor,
                y: centroid.y + (p.y - centroid.y) * factor)
        }
    }

    /// Emit one half's G-code: header/marker, then per-point contour moves
    /// with the per-point depth applied on the Z word.
    fileprivate static func emitHalf(
        marker: String,
        headerComment: String?,
        points: [VectorPoint],
        depths: [Double],
        straight: [Bool],
        params: InlayPocketParams,
        maxDepth: Double
    ) -> InlayPairedOpHalf {
        var gcode: [String] = ["%", marker]
        if let c = headerComment { gcode.append(c) }
        gcode.append("(Tip Ø \(String(format: "%.3f", params.tipDiameterMm))mm · glue gap \(String(format: "%.3f", params.glueGapMm))mm · fudge \(String(format: "%.4f", params.compressionFudge)) · maxDepth \(String(format: "%.2f", maxDepth))mm)")
        var length = 0.0
        var i = 0
        while i < points.count {
            let p = points[i]
            let d = depths.indices.contains(i) ? depths[i] : maxDepth
            gcode.append("G0 X\(fmt(p.x)) Y\(fmt(p.y))")
            gcode.append("G1 Z\(-d) F\(Int(params.plungeFeedRateMmPerMin))")
            let start = i
            i += 1
            while i < points.count {
                let q = points[i]
                let dq = depths.indices.contains(i) ? depths[i] : maxDepth
                gcode.append("G1 X\(fmt(q.x)) Y\(fmt(q.y)) Z\(-dq) F\(Int(params.feedRateMmPerMin))")
                if i + 1 < points.count {
                    let r = points[i + 1]
                    length += ((r.x - q.x) * (r.x - q.x) + (r.y - q.y) * (r.y - q.y)).squareRoot()
                }
                i += 1
            }
            length += ((points[start].x - points[i - 1].x) * (points[start].x - points[i - 1].x)
                     + (points[start].y - points[i - 1].y) * (points[start].y - points[i - 1].y)).squareRoot()
        }
        gcode.append("M30")
        gcode.append("%")
        let time = length / max(params.feedRateMmPerMin, 1) * 60.0
        return InlayPairedOpHalf(
            path: VectorPath(name: marker, points: points, isClosed: true),
            depthsMm: depths,
            straightWallFlags: straight,
            gcodeLines: gcode,
            estimatedTimeSeconds: time)
    }

    fileprivate static func fmt(_ v: Double) -> String { String(format: "%.4f", v) }
}

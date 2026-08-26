import Foundation

// MARK: - V-Carve Strategy Parameters

/// Configuration for a V-carve toolpath operation.
public struct VCarveParams: Codable, Sendable {
    
    /// Angle of the V-bit in degrees (30°, 45°, or 90°).
    public var vBitAngleDegrees: Double
    
    /// Feed rate in mm/min for cutting.
    public var feedRateMmPerMin: Double
    
    /// Plunge/feed rate in mm/min for Z-axis movement.
    public var plungeFeedRateMmPerMin: Double
    
    /// Maximum depth of cut per pass in mm.
    public var maxDepthOfCutMm: Double
    
    /// Lead-in distance in mm.
    public var leadInDistanceMm: Double
    
    /// Lead-out distance in mm.
    public var leadOutDistanceMm: Double
    
    /// Step-over distance in mm (for multi-pass V-carve).
    public var stepOverMm: Double
    
    /// Whether to use flat-bottom mode (constant Z depth, no angle variation).
    public var flatBottomMode: Bool
    
    /// Per-vector engraving depths (maps vector ID → max Z depth in mm).
    public var vectorDepths: [UUID: Double]

    // SPK-1136d — installer-verified §O key set (start depth, flat-depth
    // limit, corner sharpen, start-point/order toggles, safe Z, ramping).
    // Additive with defaults so existing call sites and persisted documents
    // decode unchanged.
    public var startDepthMm: Double
    public var flatDepthMm: Double
    public var cornerSharpen: Bool
    public var useVectorStartPoints: Bool
    public var useVectorSelectionOrder: Bool
    public var safeZHeightMm: Double
    public var rampPlungeMoves: Bool

    // SPK-VCarveClear — clearance-tool pass before the V-bit for wide/deep
    // areas (LEAN P0). A flat end mill clears the open bands inside the
    // vectors' bounding box (minus a tool-radius margin around every vector)
    // down to `clearanceDepthMm`; the V-bit then cuts the fine detail.
    // Additive with defaults — existing docs and call sites decode unchanged.
    public var clearancePassEnabled: Bool
    public var clearanceToolDiameterMm: Double
    public var clearanceDepthMm: Double
    public var clearanceStepOverMm: Double

    // SPK-1133b — linked spindle RPM (0 = not configured; recalc fills it
    // from the assigned tool's cut data and engines emit M3 S).
    public var spindleRpm: Double

    // SPK-2010b — valley-following V-carve: Z derives from the LOCAL channel
    // half-width (medial-axis distance), and closed vectors additionally get
    // a skeleton pass so the interior is actually visited. Additive with
    // defaults so pre-2010 documents decode unchanged.
    public var medialAxisPass: Bool
    public var medialAxisCellMm: Double

    // SPK-2010c — where the ridge's clearance exceeds what the V-bit can
    // widen to at max depth (× threshold factor), the bit bottoms out and
    // leaves stock beside the spine; the sweep clears those runs laterally.
    // Off by default. Additive with defaults.
    public var flatAreaClearing: Bool
    public var flatAreaThresholdFactor: Double
    public var flatAreaStepOverMm: Double

    // SPK-2120b — flat tip diameter at the V-bit point. 0 = sharp point
    // (today's goldens stay byte-stable). Wide valley depth changes when
    // tip > 0: z = -((halfWidth − tip/2) / tan(halfAngle)). Reuses the
    // inlay formula: d = (W − t) / (2·tan(A/2)) for full width W.
    public var tipDiameterMm: Double
    /// SPK-2120b — inlay rim order toggle. Default OFF (ordinary V-carve:
    // clearance-pass first if enabled, then V-bit). When ON, the V-bit
    // cuts first; the follow-up pass is around-letter clearance unless
    // `inlayInteriorFloor` is also on.
    public var vFirst: Bool
    /// SPK-2120b — when true (inlay pocket only), the follow-up pass
    /// scanline-fills each closed interior. Ordinary V-carve must leave
    /// this false so a sign's letters are not pocketed out.
    public var inlayInteriorFloor: Bool

    public init(
        vBitAngleDegrees: Double = 90.0,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        maxDepthOfCutMm: Double = 2.0,
        leadInDistanceMm: Double = 5.0,
        leadOutDistanceMm: Double = 5.0,
        stepOverMm: Double = 1.0,
        flatBottomMode: Bool = false,
        vectorDepths: [UUID: Double] = [:],
        startDepthMm: Double = 0.0,
        flatDepthMm: Double = 1.0,
        cornerSharpen: Bool = false,
        useVectorStartPoints: Bool = true,
        useVectorSelectionOrder: Bool = false,
        safeZHeightMm: Double = 3.2,
        rampPlungeMoves: Bool = false,
        clearancePassEnabled: Bool = false,
        clearanceToolDiameterMm: Double = 6.0,
        clearanceDepthMm: Double = 1.0,
        clearanceStepOverMm: Double = 0.4,
        spindleRpm: Double = 0,
        medialAxisPass: Bool = true,
        medialAxisCellMm: Double = 1.0,
        flatAreaClearing: Bool = false,
        flatAreaThresholdFactor: Double = 1.5,
        flatAreaStepOverMm: Double = 1.0,
        tipDiameterMm: Double = 0.1,
        vFirst: Bool = false,
        inlayInteriorFloor: Bool = false
    ) {
        self.vBitAngleDegrees = vBitAngleDegrees
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.maxDepthOfCutMm = maxDepthOfCutMm
        self.leadInDistanceMm = leadInDistanceMm
        self.leadOutDistanceMm = leadOutDistanceMm
        self.stepOverMm = stepOverMm
        self.flatBottomMode = flatBottomMode
        self.vectorDepths = vectorDepths
        self.startDepthMm = startDepthMm
        self.flatDepthMm = flatDepthMm
        self.cornerSharpen = cornerSharpen
        self.useVectorStartPoints = useVectorStartPoints
        self.useVectorSelectionOrder = useVectorSelectionOrder
        self.safeZHeightMm = safeZHeightMm
        self.rampPlungeMoves = rampPlungeMoves
        self.clearancePassEnabled = clearancePassEnabled
        self.clearanceToolDiameterMm = clearanceToolDiameterMm
        self.clearanceDepthMm = clearanceDepthMm
        self.clearanceStepOverMm = clearanceStepOverMm
        self.spindleRpm = spindleRpm
        self.medialAxisPass = medialAxisPass
        self.medialAxisCellMm = medialAxisCellMm
        self.flatAreaClearing = flatAreaClearing
        self.flatAreaThresholdFactor = flatAreaThresholdFactor
        self.flatAreaStepOverMm = flatAreaStepOverMm
        // SPK-2120a — tip Ø default 0 keeps today's goldens byte-stable.
        self.tipDiameterMm = tipDiameterMm
        self.vFirst = vFirst
        self.inlayInteriorFloor = inlayInteriorFloor
    }

    /// SPK-2120c — Valley form shows a time warning below this cell size.
    public var showsMedialCellTimeWarning: Bool { medialAxisCellMm < 0.5 }
    
    /// Half-angle of the V-bit in radians (used for width calculations).
    public var halfAngleRadians: Double {
        (.pi / 180.0 * vBitAngleDegrees) / 2.0
    }
    
    /// Tip width at a given depth for this V-bit angle.
    /// At depth z, the cutting width = 2 * |z| * tan(halfAngle).
    public func tipWidthAtDepth(_ depth: Double) -> Double {
        2.0 * abs(depth) * tan(halfAngleRadians)
    }

    // MARK: - Codable (backward-compatible: every key decodes with a default,
    // so documents written before SPK-1136d still load).

    private enum CodingKeys: String, CodingKey {
        case vBitAngleDegrees, feedRateMmPerMin, plungeFeedRateMmPerMin
        case maxDepthOfCutMm, leadInDistanceMm, leadOutDistanceMm, stepOverMm
        case flatBottomMode, vectorDepths
        case startDepthMm, flatDepthMm, cornerSharpen, useVectorStartPoints
        case useVectorSelectionOrder, safeZHeightMm, rampPlungeMoves
        case clearancePassEnabled, clearanceToolDiameterMm, clearanceDepthMm
        case clearanceStepOverMm
        case spindleRpm
        case medialAxisPass, medialAxisCellMm
        case flatAreaClearing, flatAreaThresholdFactor, flatAreaStepOverMm
        case tipDiameterMm
        case vFirst
        case inlayInteriorFloor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vBitAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .vBitAngleDegrees) ?? 90.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1000
        plungeFeedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeFeedRateMmPerMin) ?? 300
        maxDepthOfCutMm = try c.decodeIfPresent(Double.self, forKey: .maxDepthOfCutMm) ?? 2.0
        leadInDistanceMm = try c.decodeIfPresent(Double.self, forKey: .leadInDistanceMm) ?? 5.0
        leadOutDistanceMm = try c.decodeIfPresent(Double.self, forKey: .leadOutDistanceMm) ?? 5.0
        stepOverMm = try c.decodeIfPresent(Double.self, forKey: .stepOverMm) ?? 1.0
        flatBottomMode = try c.decodeIfPresent(Bool.self, forKey: .flatBottomMode) ?? false
        vectorDepths = try c.decodeIfPresent([UUID: Double].self, forKey: .vectorDepths) ?? [:]
        startDepthMm = try c.decodeIfPresent(Double.self, forKey: .startDepthMm) ?? 0.0
        flatDepthMm = try c.decodeIfPresent(Double.self, forKey: .flatDepthMm) ?? 1.0
        cornerSharpen = try c.decodeIfPresent(Bool.self, forKey: .cornerSharpen) ?? false
        useVectorStartPoints = try c.decodeIfPresent(Bool.self, forKey: .useVectorStartPoints) ?? true
        useVectorSelectionOrder = try c.decodeIfPresent(Bool.self, forKey: .useVectorSelectionOrder) ?? false
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 3.2
        rampPlungeMoves = try c.decodeIfPresent(Bool.self, forKey: .rampPlungeMoves) ?? false
        clearancePassEnabled = try c.decodeIfPresent(Bool.self, forKey: .clearancePassEnabled) ?? false
        clearanceToolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .clearanceToolDiameterMm) ?? 6.0
        clearanceDepthMm = try c.decodeIfPresent(Double.self, forKey: .clearanceDepthMm) ?? 1.0
        clearanceStepOverMm = try c.decodeIfPresent(Double.self, forKey: .clearanceStepOverMm) ?? 0.4
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
        medialAxisPass = try c.decodeIfPresent(Bool.self, forKey: .medialAxisPass) ?? true
        medialAxisCellMm = try c.decodeIfPresent(Double.self, forKey: .medialAxisCellMm) ?? 1.0
        flatAreaClearing = try c.decodeIfPresent(Bool.self, forKey: .flatAreaClearing) ?? false
        flatAreaThresholdFactor = try c.decodeIfPresent(Double.self, forKey: .flatAreaThresholdFactor) ?? 1.5
        flatAreaStepOverMm = try c.decodeIfPresent(Double.self, forKey: .flatAreaStepOverMm) ?? 1.0
        // SPK-2120a — legacy decode: missing key = 0 (sharp point) so today's
        // goldens regenerate byte-identical.
        tipDiameterMm = try c.decodeIfPresent(Double.self, forKey: .tipDiameterMm) ?? 0
        // SPK-2120b — legacy decode: missing key = false (clearance-before-V).
        vFirst = try c.decodeIfPresent(Bool.self, forKey: .vFirst) ?? false
        inlayInteriorFloor = try c.decodeIfPresent(Bool.self, forKey: .inlayInteriorFloor) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vBitAngleDegrees, forKey: .vBitAngleDegrees)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeFeedRateMmPerMin, forKey: .plungeFeedRateMmPerMin)
        try c.encode(maxDepthOfCutMm, forKey: .maxDepthOfCutMm)
        try c.encode(leadInDistanceMm, forKey: .leadInDistanceMm)
        try c.encode(leadOutDistanceMm, forKey: .leadOutDistanceMm)
        try c.encode(stepOverMm, forKey: .stepOverMm)
        try c.encode(flatBottomMode, forKey: .flatBottomMode)
        try c.encode(vectorDepths, forKey: .vectorDepths)
        try c.encode(startDepthMm, forKey: .startDepthMm)
        try c.encode(flatDepthMm, forKey: .flatDepthMm)
        try c.encode(cornerSharpen, forKey: .cornerSharpen)
        try c.encode(useVectorStartPoints, forKey: .useVectorStartPoints)
        try c.encode(useVectorSelectionOrder, forKey: .useVectorSelectionOrder)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(rampPlungeMoves, forKey: .rampPlungeMoves)
        try c.encode(clearancePassEnabled, forKey: .clearancePassEnabled)
        try c.encode(clearanceToolDiameterMm, forKey: .clearanceToolDiameterMm)
        try c.encode(clearanceDepthMm, forKey: .clearanceDepthMm)
        try c.encode(clearanceStepOverMm, forKey: .clearanceStepOverMm)
        try c.encode(spindleRpm, forKey: .spindleRpm)
        try c.encode(medialAxisPass, forKey: .medialAxisPass)
        try c.encode(medialAxisCellMm, forKey: .medialAxisCellMm)
        try c.encode(flatAreaClearing, forKey: .flatAreaClearing)
        try c.encode(flatAreaThresholdFactor, forKey: .flatAreaThresholdFactor)
        try c.encode(flatAreaStepOverMm, forKey: .flatAreaStepOverMm)
        try c.encode(tipDiameterMm, forKey: .tipDiameterMm)
        try c.encode(vFirst, forKey: .vFirst)
        try c.encode(inlayInteriorFloor, forKey: .inlayInteriorFloor)
    }
}

// MARK: - V-Carve Result

/// Represents a computed V-carve toolpath with G-code and metadata.
public struct VCarveResult: Codable, Sendable {
    
    public let params: VCarveParams
    public let gcodeLines: [String]
    public let estimatedTimeSeconds: Double
    public let passCount: Int
    
    /// Bounding box of the toolpath in mm.
    public let boundsMinX: Double?
    public let boundsMinY: Double?
    public let boundsMaxX: Double?
    public let boundsMaxY: Double?
}

// MARK: - V-Carve Engine

/// Computes V-carve toolpaths from vector paths using a V-bit cutter.
///
/// The V-carve strategy maps per-vector Z-depth to the cutting width of the V-bit,
/// creating shaded/engraved effects where deeper cuts produce wider grooves.
public struct VCarveEngine {
    
    // MARK: - Public API
    
    /// Compute a V-carve toolpath for the given vectors and parameters.
    public static func compute(
        vectors: [VectorPath],
        params: VCarveParams,
        stockHeightMm: Double = 25.0
    ) -> VCarveResult {
        
        // Pre-compute bounding box of all vectors
        var globalMinX: Double = .infinity
        var globalMinY: Double = .infinity
        var globalMaxX: Double = -.infinity
        var globalMaxY: Double = -.infinity
        
        for vector in vectors {
            for point in vector.points {
                globalMinX = min(globalMinX, point.x)
                globalMinY = min(globalMinY, point.y)
                globalMaxX = max(globalMaxX, point.x)
                globalMaxY = max(globalMaxY, point.y)
            }
        }
        
        let hasBounds = vectors.contains { !$0.points.isEmpty }
        let boundsMinX = hasBounds ? globalMinX : nil
        let boundsMinY = hasBounds ? globalMinY : nil
        let boundsMaxX = hasBounds ? globalMaxX : nil
        let boundsMaxY = hasBounds ? globalMaxY : nil
        
        // SPK-2010b — Y-position shading removed; depth now derives from the
        // local channel width via VCarveGeometry.
        
        var allGcodeLines: [String] = []
        let feedRate = params.feedRateMmPerMin
        let plungeFeed = params.plungeFeedRateMmPerMin

        // Generate G-code header
        allGcodeLines.append("%")
        // SPK-1133b — linked spindle RPM from the assigned tool's cut data.
        // Emitted before the clearance pass so the spindle is on for the whole
        // program (VCarveClear's marker-order assertions are unaffected).
        if params.spindleRpm > 0 {
            allGcodeLines.append("M3 S\(Int(params.spindleRpm))")
        }
        if params.clearancePassEnabled,
           let minX = boundsMinX, let minY = boundsMinY,
           let maxX = boundsMaxX, let maxY = boundsMaxY {
            // SPK-2120b — inlay rim order: when vFirst is ON, the V-bit cuts
            // the walls FIRST, then the floor is cleared. Ordinary V-carve
            // (vFirst OFF) keeps clearance-before-V.
            if params.vFirst {
                // V-bit detail pass first (appended after this block below).
                if params.inlayInteriorFloor {
                    allGcodeLines.append("(Inlay: V-walls first, then floor clearance)")
                } else {
                    allGcodeLines.append("(V-walls first, then around-letter clearance)")
                }
            } else {
                // SPK-VCarveClear: clearance pass FIRST (flat end mill clears
                // the wide open areas), then the V-bit detail pass.
                allGcodeLines.append(contentsOf: clearanceGcode(
                    vectors: vectors,
                    params: params,
                    bounds: (minX, minY, maxX, maxY)
                ))
            }
        }
        allGcodeLines.append("O=V_CARVE_TOOLPATH")
        allGcodeLines.append("(V-Bit: \(Int(params.vBitAngleDegrees))°)")
        allGcodeLines.append("(Flat Bottom: \(params.flatBottomMode ? "Yes" : "No"))")
        
        var totalCuttingLength = 0.0
        var maxPassCount = 0
        
        for vector in vectors {
            guard vector.points.count >= 2 else { continue }
            
            // Determine the max depth for this vector
            let maxDepth = params.vectorDepths[vector.id] ?? params.maxDepthOfCutMm
            
            // Calculate number of passes:
            // The V-bit tip width at max depth determines how wide the cut is.
            // We need enough passes (stepovers) to cover that width.
            let tipWidthAtMaxDepth = params.tipWidthAtDepth(maxDepth)
            // Zero/negative step-over would make Int(ceil(x/0)) trap (inf→Int
            // conversion); a zero tip width (maxDepth 0) gives 0/0 = NaN which
            // also traps. Fall back to 1 pass in both cases.
            let passCount: Int
            if params.stepOverMm > 0, tipWidthAtMaxDepth > 0 {
                passCount = max(1, Int(ceil(tipWidthAtMaxDepth / params.stepOverMm)))
            } else {
                passCount = 1
            }
            maxPassCount = max(maxPassCount, passCount)
            
            for pass in 1...passCount {
                // Scale depth proportionally per pass
                let depthFactor = Double(pass) / Double(passCount)
                let zDepth = -maxDepth * depthFactor
                
                // In flat-bottom mode, use constant Z; otherwise vary by pass
                let actualZ = params.flatBottomMode ? -maxDepth : zDepth
                
                allGcodeLines.append("")
                allGcodeLines.append("(Pass \(pass)/\(passCount), Z=\(String(format: "%.3f", actualZ)))")
                
                // Rapid to safe height
                allGcodeLines.append("G0 Z5.0")
                
                // SPK-2010b — the plunge depth at the FIRST point comes from
                // the local channel width too. Plunging to the raw pass depth
                // let a 2mm slot and a 12mm channel both bottom out at the
                // depth limit; width drives the entry as well as the middle.
                var lastZ = actualZ
                if let startPoint = vector.points.first {
                    let startHalfWidth = VCarveGeometry.distanceToNearestOtherEdge(
                        vector, index: 0, allVectors: vectors)
                    let widthZ = VCarveGeometry.depthForHalfWidth(
                        startHalfWidth, angle: params.vBitAngleDegrees, maxDepth: maxDepth,
                        tipDiameterMm: params.tipDiameterMm)
                    // Never exceed this pass's depth clamp.
                    let startZ = max(widthZ, actualZ)
                    lastZ = startZ
                    let leadInX = startPoint.x - params.leadInDistanceMm
                    allGcodeLines.append(
                        "G0 X\(String(format: "%.3f", leadInX)) Y\(String(format: "%.3f", startPoint.y))"
                    )
                    allGcodeLines.append("G1 Z\(String(format: "%.3f", startZ)) F\(Int(plungeFeed))")
                    
                    // Move to start with feed rate
                    allGcodeLines.append(
                        "G1 X\(String(format: "%.3f", startPoint.x)) Y\(String(format: "%.3f", startPoint.y)) F\(Int(feedRate))"
                    )
                }
                
                // Follow the vector path
                for i in 1..<vector.points.count {
                    let point = vector.points[i]
                    
                    // SPK-2010b — Z from the LOCAL CHANNEL WIDTH (distance to
                    // the nearest edge that is not this vertex's own two wall
                    // segments), never from page position. A V-bit can only
                    // sink as deep as the available width allows:
                    // z = -(halfWidth / tan(halfAngle)), clamped to the pass.
                    let halfWidth = VCarveGeometry.distanceToNearestOtherEdge(
                        vector, index: i, allVectors: vectors)
                    var z = VCarveGeometry.depthForHalfWidth(
                        halfWidth, angle: params.vBitAngleDegrees, maxDepth: maxDepth,
                        tipDiameterMm: params.tipDiameterMm)
                    // Never exceed this pass's depth clamp (flat-bottom mode
                    // sets actualZ = -maxDepth, forcing a truly flat pass).
                    z = max(z, actualZ)
                    lastZ = z
                    allGcodeLines.append(
                        "G1 X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y)) Z\(String(format: "%.3f", z)) F\(Int(feedRate))"
                    )
                }
                
                // Close the path if vector is closed
                if vector.isClosed && vector.points.count > 2 {
                    let firstPoint = vector.points.first!
                    allGcodeLines.append(
                        "G1 X\(String(format: "%.3f", firstPoint.x)) Y\(String(format: "%.3f", firstPoint.y)) Z\(String(format: "%.3f", lastZ)) F\(Int(feedRate))"
                    )
                }
                
                // Lead-out at end point, at the depth the cut ended on.
                if let endPoint = vector.points.last {
                    let leadOutX = endPoint.x + params.leadOutDistanceMm
                    allGcodeLines.append(
                        "G1 X\(String(format: "%.3f", leadOutX)) Y\(String(format: "%.3f", endPoint.y)) Z\(String(format: "%.3f", lastZ)) F\(Int(feedRate))"
                    )
                }
                
                // Rapid to safe height
                allGcodeLines.append("G0 Z5.0")
            }
            
            totalCuttingLength += vector.length
            
            // ---- SPK-2010b: medial-axis (skeleton) pass ----
            //
            // Tracing the outline alone leaves the middle of a closed shape
            // uncut — the V-bit must ride the valley spine, where the shape is
            // widest. Depth along each ridge point comes from its clearance.
            if params.medialAxisPass, vector.isClosed, vector.points.count >= 3 {
                let skeleton = MedialAxis.compute(
                    outline: vector.points, cellMm: params.medialAxisCellMm)
                if !skeleton.isEmpty {
                    allGcodeLines.append("")
                    allGcodeLines.append(
                        "(Medial axis: \(skeleton.paths.count) ridge path(s), max clearance \(String(format: "%.3f", skeleton.maxClearanceMm))mm)")
                    
                    for path in skeleton.paths where path.count >= 2 {
                        allGcodeLines.append("G0 Z5.0")
                        
                        let head = path[0]
                        // depthForHalfWidth already returns a negative,
                        // maxDepth-clamped Z — never negate it again.
                        let headZ = VCarveGeometry.depthForHalfWidth(
                            head.clearanceMm, angle: params.vBitAngleDegrees,
                            maxDepth: maxDepth, tipDiameterMm: params.tipDiameterMm)
                        
                        allGcodeLines.append(
                            "G0 X\(String(format: "%.3f", head.position.x)) Y\(String(format: "%.3f", head.position.y))"
                        )
                        allGcodeLines.append("G1 Z\(String(format: "%.3f", headZ)) F\(Int(plungeFeed))")
                        
                        for pt in path.dropFirst() {
                            // Wide spine = deeper cut; narrow neck stays shallow.
                            let z = VCarveGeometry.depthForHalfWidth(
                                pt.clearanceMm, angle: params.vBitAngleDegrees,
                                maxDepth: maxDepth, tipDiameterMm: params.tipDiameterMm)
                            allGcodeLines.append(
                                "G1 X\(String(format: "%.3f", pt.position.x)) Y\(String(format: "%.3f", pt.position.y)) Z\(String(format: "%.3f", z)) F\(Int(feedRate))"
                            )
                        }
                        
                        allGcodeLines.append("G0 Z5.0")
                        totalCuttingLength += medialPathLength(path)
                    }
                    
                    // ---- SPK-2010c: flat-area clearing (optional) ----
                    if params.flatAreaClearing {
                        allGcodeLines.append(contentsOf: flatAreaSweep(
                            skeleton, params: params, maxDepth: maxDepth))
                    }
                }
            }
        }
        
        // SPK-2120b — vFirst follow-up runs BEFORE the final program end so
        // GRBL actually cuts it (not stranded after M30/%).
        // Inlay pocket: interior floor fill. Ordinary V-carve: around-letter
        // clearance so a sign's glyphs are not pocketed out.
        if params.clearancePassEnabled, params.vFirst {
            allGcodeLines.append("")
            if params.inlayInteriorFloor {
                allGcodeLines.append("(Inlay: floor clearance after V-walls)")
                allGcodeLines.append(contentsOf: inlayFloorGcode(vectors: vectors, params: params))
            } else if let minX = boundsMinX, let minY = boundsMinY,
                      let maxX = boundsMaxX, let maxY = boundsMaxY {
                allGcodeLines.append("(V-walls first, then around-letter clearance)")
                allGcodeLines.append(contentsOf: clearanceGcode(
                    vectors: vectors,
                    params: params,
                    bounds: (minX, minY, maxX, maxY)
                ))
            }
        }

        // Add G-code footer — single program end AFTER everything ran.
        allGcodeLines.append("")
        allGcodeLines.append("M30")
        allGcodeLines.append("%")
        
        // Calculate estimated time (rough approximation)
        let cuttingTime = totalCuttingLength * Double(maxPassCount) / feedRate * 60.0
        
        return VCarveResult(
            params: params,
            gcodeLines: allGcodeLines,
            estimatedTimeSeconds: cuttingTime,
            passCount: maxPassCount,
            boundsMinX: boundsMinX,
            boundsMinY: boundsMinY,
            boundsMaxX: boundsMaxX,
            boundsMaxY: boundsMaxY
        )
    }

    /// Length of a medial-axis ridge polyline (for the time estimate).
    private static func medialPathLength(_ path: [MedialAxis.RidgePoint]) -> Double {
        guard path.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<path.count {
            let a = path[i - 1].position, b = path[i].position
            total += hypot(b.x - a.x, b.y - a.y)
        }
        return total
    }

    /// SPK-2010c — sweep the too-wide segments of the medial-axis ridge at
    /// full depth. A ridge point is "flat" when its clearance exceeds the
    /// V-bit's reachable half-width at max depth (tipWidthAtDepth/2) by the
    /// threshold factor. For each flat run, lateral passes step across the
    /// extra width on BOTH sides of the spine at −maxDepth, so the fat region
    /// bottoms out instead of keeping a stock ridge beside the spine.
    static func flatAreaSweep(
        _ skeleton: MedialAxis.Result,
        params: VCarveParams,
        maxDepth: Double
    ) -> [String] {
        let tipHalf = params.tipWidthAtDepth(maxDepth) / 2.0
        let threshold = max(tipHalf * params.flatAreaThresholdFactor, tipHalf + 1e-6)
        let zFlat = -maxDepth
        let feed = Int(params.feedRateMmPerMin)
        let plunge = Int(params.plungeFeedRateMmPerMin)

        var g: [String] = []

        for path in skeleton.paths {
            // Split the ridge into maximal runs where clearance >= threshold.
            var i = 0
            while i < path.count {
                if path[i].clearanceMm < threshold { i += 1; continue }
                var j = i
                while j + 1 < path.count && path[j + 1].clearanceMm >= threshold { j += 1 }

                // Flat run [i...j]: sweep laterally. The extra half-width each
                // side of the spine that the V-bit cannot reach:
                let extra = path[i].clearanceMm - tipHalf
                if extra > 1e-6 {
                    let ax = path[i].position.x, ay = path[i].position.y
                    let bx = path[j].position.x, by = path[j].position.y
                    let dx = bx - ax, dy = by - ay
                    let len = hypot(dx, dy)
                    if len > 1e-9 {
                        let px = -dy / len, py = dx / len // unit perpendicular
                        let sweeps = max(1, Int(ceil(extra * 2 / max(params.flatAreaStepOverMm, 0.05))))

                        for s in 0...sweeps {
                            // Offsets straddle the spine: 0, +step, −step, +2·step, …
                            let off = Double((s + 1) / 2) * (s % 2 == 1 ? 1.0 : -1.0)
                                * params.flatAreaStepOverMm
                            if abs(off) > extra { continue } // stay inside the flat band

                            g.append("G0 Z5.0")
                            g.append("G0 X\(String(format: "%.3f", ax + px * off)) Y\(String(format: "%.3f", ay + py * off))")
                            g.append("G1 Z\(String(format: "%.3f", zFlat)) F\(plunge)")
                            g.append("G1 X\(String(format: "%.3f", bx + px * off)) Y\(String(format: "%.3f", by + py * off)) F\(feed)")
                            g.append("G0 Z5.0")
                        }
                    }
                }

                i = j + 1
            }
        }

        if !g.isEmpty {
            g.insert("(Flat area clearing: regions wider than \(String(format: "%.3f", tipHalf * 2))mm tip width)", at: 0)
        }

        return g
    }

    /// SPK-2120b — inlay FLOOR pass: raster the shape INTERIOR flat at
    /// `clearanceDepthMm` with the endmill, after the V-bit has cut the walls.
    /// Unlike `clearanceGcode` (sign-board semantics: clear AROUND protected
    /// letters), an inlay pocket's interior IS the floor, so each closed
    /// vector is scanline-filled, inset by the tool radius to leave the
    /// V-walls untouched.
    private static func inlayFloorGcode(
        vectors: [VectorPath],
        params: VCarveParams
    ) -> [String] {
        let toolR = params.clearanceToolDiameterMm / 2.0
        let step = max(params.clearanceStepOverMm * params.clearanceToolDiameterMm, 1e-3)
        guard toolR > 1e-9 else { return [] }

        let z = -params.clearanceDepthMm
        let feed = Int(params.feedRateMmPerMin), plunge = Int(params.plungeFeedRateMmPerMin)
        func f(_ v: Double) -> String { String(format: "%.3f", v) }

        var lines: [String] = []
        var leftToRight = true

        for vector in vectors {
            guard vector.isClosed, let poly = SpecialtyBoundary.polygonPoints(of: vector) else { continue }
            let ys = poly.map(\.y)
            guard let minY = ys.min(), let maxY = ys.max(), maxY - minY > 2 * toolR else { continue }

            var rows: [String] = []
            var y = minY + toolR
            while y <= maxY - toolR {
                for run in SpecialtyBoundary.insideRuns(of: poly, y: y) {
                    // Inset each run so the endmill never touches the V-walls.
                    let x0 = run.x0 + toolR, x1 = run.x1 - toolR
                    guard x1 - x0 > 1e-6 else { continue }
                    let (a, b) = leftToRight ? (x0, x1) : (x1, x0)
                    rows.append("G0 Z5.0")
                    rows.append("G0 X\(f(a)) Y\(f(y))")
                    rows.append("G1 Z\(f(z)) F\(plunge)")
                    rows.append("G1 X\(f(b)) Y\(f(y)) F\(feed)")
                    leftToRight.toggle()
                }
                y += step
            }
            guard !rows.isEmpty else { continue }

            if lines.isEmpty {
                lines.append("O=VCARVE_CLEARANCE")
                lines.append("(Clearance tool: \(String(format: "%.1f", params.clearanceToolDiameterMm))mm)")
                lines.append("(Floor depth: \(String(format: "%.2f", params.clearanceDepthMm))mm)")
            }
            lines.append(contentsOf: rows)
        }
        if !lines.isEmpty { lines.append("G0 Z5.0") }
        return lines
    }

    /// SPK-VCarveClear — clearance pass emitted BEFORE the V-bit detail pass.
    /// A flat end mill (clearance tool) raster-clears the WIDE open bands
    /// inside the vectors' bounding box — every X-range not covered by a
    /// vector's own bounding box expanded by (tool radius + 1mm margin), so
    /// the letter strokes survive — down to `clearanceDepthMm`. The V-bit then
    /// only has to engrave the fine detail. Raster rows are spaced
    /// `clearanceStepOverMm × toolDiameter`, alternating direction.
    private static func clearanceGcode(
        vectors: [VectorPath],
        params: VCarveParams,
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)
    ) -> [String] {
        let toolR = params.clearanceToolDiameterMm / 2.0
        let step = params.clearanceStepOverMm * params.clearanceToolDiameterMm
        let margin = toolR + 1.0
        guard toolR > 1e-9, step > 1e-9,
              bounds.maxX - bounds.minX > 2 * toolR,
              bounds.maxY - bounds.minY > 2 * toolR else {
            return []
        }

        // Exclusion bands: each PROTECTED vector's X-range expanded by the
        // clearance radius + margin, with its Y-range for row overlap.
        // A vector is protected when it is strictly inside the global bounds
        // (e.g. letters inside a sign board). When nothing is strictly inside
        // (letters-only, or a single shape), every vector is protected and the
        // union bbox is the clearable region — so the clearance clears the
        // bands BETWEEN shapes, never inside one.
        let strictlyInside: [VectorPath] = vectors.filter { v in
            guard !v.points.isEmpty else { return false }
            let xs = v.points.map { $0.x }
            let ys = v.points.map { $0.y }
            return xs.min()! > bounds.minX + 1e-6
                && xs.max()! < bounds.maxX - 1e-6
                && ys.min()! > bounds.minY + 1e-6
                && ys.max()! < bounds.maxY - 1e-6
        }
        let protectAll = strictlyInside.isEmpty
        let exclusions: [(minX: Double, maxX: Double, minY: Double, maxY: Double)] = vectors.compactMap { v in
            guard !v.points.isEmpty else { return nil }
            let xs = v.points.map { $0.x }
            let ys = v.points.map { $0.y }
            let vMinX = xs.min()!, vMaxX = xs.max()!, vMinY = ys.min()!, vMaxY = ys.max()!
            let isInside = vMinX > bounds.minX + 1e-6
                && vMaxX < bounds.maxX - 1e-6
                && vMinY > bounds.minY + 1e-6
                && vMaxY < bounds.maxY - 1e-6
            guard protectAll || isInside else { return nil }
            return (vMinX - margin, vMaxX + margin, vMinY, vMaxY)
        }

        let depth = -params.clearanceDepthMm
        var lines: [String] = []
        lines.append("")
        lines.append("O=VCARVE_CLEARANCE")
        lines.append("(Clearance tool: \(String(format: "%.1f", params.clearanceToolDiameterMm))mm)")
        lines.append("(Clearance depth: \(String(format: "%.2f", params.clearanceDepthMm))mm)")

        var y = bounds.minY + toolR
        var leftToRight = true
        while y <= bounds.maxY - toolR {
            // Open gaps on this row: [minX+toolR, maxX-toolR] minus the bands
            // of vectors whose Y-range overlaps this row.
            let rowBands = exclusions
                .filter { y >= $0.minY - toolR && y <= $0.maxY + toolR }
                .sorted { $0.minX < $1.minX }
            var gaps: [(Double, Double)] = []
            var cursor = bounds.minX + toolR
            for band in rowBands {
                let bandStart = max(cursor, band.minX)
                if bandStart < bounds.maxX - toolR && bandStart > cursor + 1e-6 {
                    gaps.append((cursor, min(bandStart, bounds.maxX - toolR)))
                }
                cursor = max(cursor, band.maxX)
                if cursor >= bounds.maxX - toolR { break }
            }
            if cursor < bounds.maxX - toolR - 1e-6 {
                gaps.append((cursor, bounds.maxX - toolR))
            }

            for gap in gaps {
                let x0 = leftToRight ? gap.0 : gap.1
                let x1 = leftToRight ? gap.1 : gap.0
                lines.append("G0 Z5.0")
                lines.append("G0 X\(String(format: "%.3f", x0)) Y\(String(format: "%.3f", y))")
                lines.append("G1 Z\(String(format: "%.3f", depth)) F\(Int(params.plungeFeedRateMmPerMin))")
                lines.append("G1 X\(String(format: "%.3f", x1)) Y\(String(format: "%.3f", y)) F\(Int(params.feedRateMmPerMin))")
                leftToRight.toggle()
            }
            y += step
        }
        return lines
    }
}

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
        clearanceStepOverMm: Double = 0.4
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
    }
    
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
        
        // Compute per-vector bounding boxes for shading
        var vectorBounds: [UUID: (minY: Double, maxY: Double)] = [:]
        for vector in vectors {
            guard !vector.points.isEmpty else { continue }
            let ys = vector.points.map { $0.y }
            vectorBounds[vector.id] = (ys.min()!, ys.max()!)
        }
        
        var allGcodeLines: [String] = []
        let feedRate = params.feedRateMmPerMin
        let plungeFeed = params.plungeFeedRateMmPerMin

        // Generate G-code header
        allGcodeLines.append("%")
        if params.clearancePassEnabled,
           let minX = boundsMinX, let minY = boundsMinY,
           let maxX = boundsMaxX, let maxY = boundsMaxY {
            // SPK-VCarveClear: clearance pass FIRST (flat end mill clears the
            // wide open areas), then the V-bit detail pass.
            allGcodeLines.append(contentsOf: clearanceGcode(
                vectors: vectors,
                params: params,
                bounds: (minX, minY, maxX, maxY)
            ))
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
            let passCount = max(1, Int(ceil(tipWidthAtMaxDepth / params.stepOverMm)))
            maxPassCount = max(maxPassCount, passCount)
            
            // Get bounding box Y-range for shading interpolation
            let (vecMinY, vecMaxY) = vectorBounds[vector.id] ?? (0, 1)
            let yRange = vecMaxY - vecMinY
            
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
                
                // Move to start point with lead-in
                if let startPoint = vector.points.first {
                    let leadInX = startPoint.x - params.leadInDistanceMm
                    allGcodeLines.append(
                        "G0 X\(String(format: "%.3f", leadInX)) Y\(String(format: "%.3f", startPoint.y))"
                    )
                    allGcodeLines.append("G1 Z\(String(format: "%.3f", actualZ)) F\(Int(plungeFeed))")
                    
                    // Move to start with feed rate
                    allGcodeLines.append(
                        "G1 X\(String(format: "%.3f", startPoint.x)) Y\(String(format: "%.3f", startPoint.y)) F\(Int(feedRate))"
                    )
                }
                
                // Follow the vector path
                for i in 1..<vector.points.count {
                    let point = vector.points[i]
                    
                    // V-carve shading: Z varies along the path based on the point's
                    // Y position relative to the vector's bounding box.
                    // Higher Y → lighter (shallower Z), Lower Y → darker (deeper Z).
                    if yRange > 1e-9 {
                        let normalizedY = 1.0 - (point.y - vecMinY) / yRange
                        let shadedZ = actualZ * (0.3 + 0.7 * normalizedY)
                        allGcodeLines.append(
                            "G1 X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y)) Z\(String(format: "%.3f", shadedZ)) F\(Int(feedRate))"
                        )
                    } else {
                        // Single-height vector: constant Z
                        allGcodeLines.append(
                            "G1 X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y)) Z\(String(format: "%.3f", actualZ)) F\(Int(feedRate))"
                        )
                    }
                }
                
                // Close the path if vector is closed
                if vector.isClosed && vector.points.count > 2 {
                    let firstPoint = vector.points.first!
                    allGcodeLines.append(
                        "G1 X\(String(format: "%.3f", firstPoint.x)) Y\(String(format: "%.3f", firstPoint.y)) Z\(String(format: "%.3f", actualZ)) F\(Int(feedRate))"
                    )
                }
                
                // Lead-out at end point
                if let endPoint = vector.points.last {
                    let leadOutX = endPoint.x + params.leadOutDistanceMm
                    allGcodeLines.append(
                        "G1 X\(String(format: "%.3f", leadOutX)) Y\(String(format: "%.3f", endPoint.y)) Z\(String(format: "%.3f", actualZ)) F\(Int(feedRate))"
                    )
                }
                
                // Rapid to safe height
                allGcodeLines.append("G0 Z5.0")
            }
            
            totalCuttingLength += vector.length
        }
        
        // Add G-code footer
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

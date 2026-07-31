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
    
    public init(
        vBitAngleDegrees: Double = 90.0,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        maxDepthOfCutMm: Double = 2.0,
        leadInDistanceMm: Double = 5.0,
        leadOutDistanceMm: Double = 5.0,
        stepOverMm: Double = 1.0,
        flatBottomMode: Bool = false,
        vectorDepths: [UUID: Double] = [:]
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
    }
    
    /// Half-angle of the V-bit in radians (used for width calculations).
    public var halfAngleRadians: Double {
        (.pi / 180.0 * vBitAngleDegrees) / 2.0
    }
    
    /// Tip width at a given depth for this V-bit angle.
    /// At depth z, the cutting width = 2 * |z| * tan(halfAngle).
    public func tipWidthAtDepth(_ depth: Double) -> Double {
        abs(depth) * tan(halfAngleRadians)
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
}

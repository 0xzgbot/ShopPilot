import Foundation

// MARK: - Quick Engrave Parameters

/// Configuration for a quick engrave toolpath operation.
///
/// Quick engrave is a simplified single-pass V-carve designed for speed.
/// It produces one pass per vector with no stepover — ideal for hobbyists
/// who want to engrave text or simple vectors quickly.
public struct QuickEngraveParams: Codable, Sendable {
    
    /// Angle of the V-bit in degrees (30°, 45°, or 90°).
    public var vBitAngleDegrees: Double
    
    /// Feed rate in mm/min for cutting.
    public var feedRateMmPerMin: Double
    
    /// Plunge/feed rate in mm/min for Z-axis movement.
    public var plungeFeedRateMmPerMin: Double
    
    /// Depth of cut in mm (single pass, always this depth).
    public var depthMm: Double
    
    /// Lead-in distance in mm.
    public var leadInDistanceMm: Double
    
    /// Lead-out distance in mm.
    public var leadOutDistanceMm: Double
    
    /// Per-vector engraving depths (maps vector ID → max Z depth in mm).
    /// If a vector has an entry, that depth overrides the default `depthMm`.
    public var vectorDepths: [UUID: Double]
    
    public init(
        vBitAngleDegrees: Double = 90.0,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        depthMm: Double = 1.0,
        leadInDistanceMm: Double = 5.0,
        leadOutDistanceMm: Double = 5.0,
        vectorDepths: [UUID: Double] = [:]
    ) {
        self.vBitAngleDegrees = vBitAngleDegrees
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.depthMm = depthMm
        self.leadInDistanceMm = leadInDistanceMm
        self.leadOutDistanceMm = leadOutDistanceMm
        self.vectorDepths = vectorDepths
    }
    
    /// Half-angle of the V-bit in radians (used for width calculations).
    public var halfAngleRadians: Double {
        (.pi / 180.0 * vBitAngleDegrees) / 2.0
    }
    
    /// Tip width at a given depth for this V-bit angle.
    public func tipWidthAtDepth(_ depth: Double) -> Double {
        abs(depth) * tan(halfAngleRadians)
    }
}

// MARK: - Quick Engrave Result

/// Represents a computed quick engrave toolpath with G-code and metadata.
public struct QuickEngraveResult: Codable, Sendable {
    
    public let params: QuickEngraveParams
    public let gcodeLines: [String]
    public let estimatedTimeSeconds: Double
    /// Always 1 — quick engrave is single-pass only.
    public let passCount: Int
    
    /// Bounding box of the toolpath in mm.
    public let boundsMinX: Double?
    public let boundsMinY: Double?
    public let boundsMaxX: Double?
    public let boundsMaxY: Double?
}

// MARK: - Quick Engrave Engine

/// Computes a single-pass quick engrave toolpath from vector paths using a V-bit cutter.
///
/// Unlike VCarveEngine which does multi-pass with stepover, QuickEngraveEngine
/// produces exactly one pass per vector at a constant depth. Per-vector depth
/// overrides are supported via `vectorDepths` for basic shading effects.
public struct QuickEngraveEngine {
    
    // MARK: - Public API
    
    /// Compute a quick engrave toolpath for the given vectors and parameters.
    public static func compute(
        vectors: [VectorPath],
        params: QuickEngraveParams,
        stockHeightMm: Double = 25.0
    ) -> QuickEngraveResult {
        
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
        
        var allGcodeLines: [String] = []
        let feedRate = params.feedRateMmPerMin
        let plungeFeed = params.plungeFeedRateMmPerMin
        
        // Generate G-code header
        allGcodeLines.append("%")
        allGcodeLines.append("O=QUICK_ENGRAVE_TOOLPATH")
        allGcodeLines.append("(V-Bit: \(Int(params.vBitAngleDegrees))°)")
        allGcodeLines.append("(Quick Engrave — single pass)")
        
        var totalCuttingLength = 0.0
        
        for vector in vectors {
            guard vector.points.count >= 2 else { continue }
            
            // Determine the depth for this vector
            let depth = params.vectorDepths[vector.id] ?? params.depthMm
            
            // Single pass — always at full depth
            let zDepth = -depth
            
            allGcodeLines.append("")
            allGcodeLines.append("(Quick Engrave, Z=\(String(format: "%.3f", zDepth)))")
            
            // Rapid to safe height
            allGcodeLines.append("G0 Z5.0")
            
            // Move to start point with lead-in
            if let startPoint = vector.points.first {
                let leadInX = startPoint.x - params.leadInDistanceMm
                allGcodeLines.append(
                    "G0 X\(String(format: "%.3f", leadInX)) Y\(String(format: "%.3f", startPoint.y))"
                )
                allGcodeLines.append("G1 Z\(String(format: "%.3f", zDepth)) F\(Int(plungeFeed))")
                
                // Move to start with feed rate
                allGcodeLines.append(
                    "G1 X\(String(format: "%.3f", startPoint.x)) Y\(String(format: "%.3f", startPoint.y)) F\(Int(feedRate))"
                )
            }
            
            // Follow the vector path (constant Z — no shading)
            for i in 1..<vector.points.count {
                let point = vector.points[i]
                allGcodeLines.append(
                    "G1 X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y)) Z\(String(format: "%.3f", zDepth)) F\(Int(feedRate))"
                )
            }
            
            // Close the path if vector is closed
            if vector.isClosed && vector.points.count > 2 {
                let firstPoint = vector.points.first!
                allGcodeLines.append(
                    "G1 X\(String(format: "%.3f", firstPoint.x)) Y\(String(format: "%.3f", firstPoint.y)) Z\(String(format: "%.3f", zDepth)) F\(Int(feedRate))"
                )
            }
            
            // Lead-out at end point
            if let endPoint = vector.points.last {
                let leadOutX = endPoint.x + params.leadOutDistanceMm
                allGcodeLines.append(
                    "G1 X\(String(format: "%.3f", leadOutX)) Y\(String(format: "%.3f", endPoint.y)) Z\(String(format: "%.3f", zDepth)) F\(Int(feedRate))"
                )
            }
            
            // Rapid to safe height
            allGcodeLines.append("G0 Z5.0")
            
            totalCuttingLength += vector.length
        }
        
        // Add G-code footer
        allGcodeLines.append("")
        allGcodeLines.append("M30")
        allGcodeLines.append("%")
        
        // Calculate estimated time (single pass)
        let cuttingTime = totalCuttingLength / feedRate * 60.0
        
        return QuickEngraveResult(
            params: params,
            gcodeLines: allGcodeLines,
            estimatedTimeSeconds: cuttingTime,
            passCount: 1,
            boundsMinX: boundsMinX,
            boundsMinY: boundsMinY,
            boundsMaxX: boundsMaxX,
            boundsMaxY: boundsMaxY
        )
    }
}

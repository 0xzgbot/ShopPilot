import Foundation

// MARK: - Profile Toolpath Strategy

/// How the profile toolpath relates to the vector boundary.
public enum ProfileCutMode: String, Codable, Sendable {
    case outCut
    case inCut
    case onCut
    
    public var displayName: String {
        switch self {
        case .outCut: return "Out Cut"
        case .inCut: return "In Cut"
        case .onCut: return "On Cut"
        }
    }
}

/// Plunge/entry strategy (installer-verified: Aspire Ramping page).
public enum ProfileRampType: String, Codable, Sendable {
    case none
    case smooth
    case zigZag
    case spiral

    public var displayName: String {
        switch self {
        case .none: return "None (vertical plunge)"
        case .smooth: return "Smooth"
        case .zigZag: return "ZigZag"
        case .spiral: return "Spiral"
        }
    }
}

/// Lead-in move shape (installer-verified: Aspire Leads page).
public enum ProfileLeadType: String, Codable, Sendable {
    case none
    case straightLine
    case circularArc

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .straightLine: return "Straight Line"
        case .circularArc: return "Circular Arc"
        }
    }
}

/// Cutting direction around the part (installer-verified: Climb/Conventional).
public enum ProfileCutDirection: String, Codable, Sendable {
    case climb
    case conventional

    public var displayName: String {
        switch self {
        case .climb: return "Climb"
        case .conventional: return "Conventional"
        }
    }
}

// MARK: - Profile Toolpath Parameters

/// Configuration for a profile toolpath operation.
public struct ProfileToolpathParams: Codable, Sendable {
    
    public var cutMode: ProfileCutMode
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var maxDepthOfCutMm: Double
    public var toolDiameterMm: Double
    public var tabWidths: [Double]
    public var finishPasses: Int
    public var leadInDistanceMm: Double
    public var leadOutDistanceMm: Double

    // SPK-1133b — linked spindle RPM (0 = not configured; recalc fills it
    // from the assigned tool's cut data and engines emit M3 S).
    public var spindleRpm: Double

    // SPK-1136a — installer-verified §R2 key set (tabs / ramping / leads /
    // corners / direction). Additive with defaults so existing call sites and
    // persisted documents decode unchanged.
    public var addTabs: Bool
    public var tabLengthMm: Double
    public var tabThicknessMm: Double
    public var tabSpacingMm: Double
    public var use3DTabs: Bool
    public var rampType: ProfileRampType
    public var rampDistanceMm: Double
    public var leadInType: ProfileLeadType
    public var leadInAngleDegrees: Double
    public var circularLeadRadiusMm: Double
    public var doLeadOut: Bool
    public var sharpExternalCorner: Bool
    public var sharpInternalCorner: Bool
    public var cutDirection: ProfileCutDirection
    
    public init(
        cutMode: ProfileCutMode = .onCut,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        maxDepthOfCutMm: Double = 2.0,
        toolDiameterMm: Double = 6.0,
        tabWidths: [Double] = [],
        finishPasses: Int = 1,
        leadInDistanceMm: Double = 5.0,
        leadOutDistanceMm: Double = 5.0,
        spindleRpm: Double = 0,
        addTabs: Bool = false,
        tabLengthMm: Double = 6.0,
        tabThicknessMm: Double = 3.0,
        tabSpacingMm: Double = 25.0,
        use3DTabs: Bool = false,
        rampType: ProfileRampType = .smooth,
        rampDistanceMm: Double = 3.0,
        leadInType: ProfileLeadType = .none,
        leadInAngleDegrees: Double = 45.0,
        circularLeadRadiusMm: Double = 2.0,
        doLeadOut: Bool = false,
        sharpExternalCorner: Bool = false,
        sharpInternalCorner: Bool = false,
        cutDirection: ProfileCutDirection = .climb
    ) {
        self.cutMode = cutMode
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.maxDepthOfCutMm = maxDepthOfCutMm
        self.toolDiameterMm = toolDiameterMm
        self.tabWidths = tabWidths
        self.finishPasses = finishPasses
        self.leadInDistanceMm = leadInDistanceMm
        self.leadOutDistanceMm = leadOutDistanceMm
        self.spindleRpm = spindleRpm
        self.addTabs = addTabs
        self.tabLengthMm = tabLengthMm
        self.tabThicknessMm = tabThicknessMm
        self.tabSpacingMm = tabSpacingMm
        self.use3DTabs = use3DTabs
        self.rampType = rampType
        self.rampDistanceMm = rampDistanceMm
        self.leadInType = leadInType
        self.leadInAngleDegrees = leadInAngleDegrees
        self.circularLeadRadiusMm = circularLeadRadiusMm
        self.doLeadOut = doLeadOut
        self.sharpExternalCorner = sharpExternalCorner
        self.sharpInternalCorner = sharpInternalCorner
        self.cutDirection = cutDirection
    }
    
    /// Create params from material defaults (overrides only feed rate).
    public static func fromMaterial(_ material: Material, toolDiameter: Double) -> ProfileToolpathParams {
        let params = ProfileToolpathParams(
            cutMode: .onCut,
            feedRateMmPerMin: material.maxFeedRateMmPerMin * 0.7,
            plungeFeedRateMmPerMin: material.maxFeedRateMmPerMin * 0.3,
            maxDepthOfCutMm: min(material.maxDepthOfCutMm, toolDiameter),
            toolDiameterMm: toolDiameter,
            tabWidths: [],
            finishPasses: 1,
            leadInDistanceMm: toolDiameter * 2,
            leadOutDistanceMm: toolDiameter * 2
        )
        return params
    }

    // MARK: - Codable (backward-compatible: every key decodes with a default,
    // so documents written before SPK-1136a still load).

    private enum CodingKeys: String, CodingKey {
        case cutMode, feedRateMmPerMin, plungeFeedRateMmPerMin, maxDepthOfCutMm
        case toolDiameterMm, tabWidths, finishPasses, leadInDistanceMm, leadOutDistanceMm
        case spindleRpm
        case addTabs, tabLengthMm, tabThicknessMm, tabSpacingMm, use3DTabs
        case rampType, rampDistanceMm, leadInType, leadInAngleDegrees
        case circularLeadRadiusMm, doLeadOut, sharpExternalCorner, sharpInternalCorner
        case cutDirection
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cutMode = try c.decodeIfPresent(ProfileCutMode.self, forKey: .cutMode) ?? .onCut
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1000
        plungeFeedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeFeedRateMmPerMin) ?? 300
        maxDepthOfCutMm = try c.decodeIfPresent(Double.self, forKey: .maxDepthOfCutMm) ?? 2.0
        toolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .toolDiameterMm) ?? 6.0
        tabWidths = try c.decodeIfPresent([Double].self, forKey: .tabWidths) ?? []
        finishPasses = try c.decodeIfPresent(Int.self, forKey: .finishPasses) ?? 1
        leadInDistanceMm = try c.decodeIfPresent(Double.self, forKey: .leadInDistanceMm) ?? 5.0
        leadOutDistanceMm = try c.decodeIfPresent(Double.self, forKey: .leadOutDistanceMm) ?? 5.0
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
        addTabs = try c.decodeIfPresent(Bool.self, forKey: .addTabs) ?? false
        tabLengthMm = try c.decodeIfPresent(Double.self, forKey: .tabLengthMm) ?? 6.0
        tabThicknessMm = try c.decodeIfPresent(Double.self, forKey: .tabThicknessMm) ?? 3.0
        tabSpacingMm = try c.decodeIfPresent(Double.self, forKey: .tabSpacingMm) ?? 25.0
        use3DTabs = try c.decodeIfPresent(Bool.self, forKey: .use3DTabs) ?? false
        rampType = try c.decodeIfPresent(ProfileRampType.self, forKey: .rampType) ?? .smooth
        rampDistanceMm = try c.decodeIfPresent(Double.self, forKey: .rampDistanceMm) ?? 3.0
        leadInType = try c.decodeIfPresent(ProfileLeadType.self, forKey: .leadInType) ?? .none
        leadInAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .leadInAngleDegrees) ?? 45.0
        circularLeadRadiusMm = try c.decodeIfPresent(Double.self, forKey: .circularLeadRadiusMm) ?? 2.0
        doLeadOut = try c.decodeIfPresent(Bool.self, forKey: .doLeadOut) ?? false
        sharpExternalCorner = try c.decodeIfPresent(Bool.self, forKey: .sharpExternalCorner) ?? false
        sharpInternalCorner = try c.decodeIfPresent(Bool.self, forKey: .sharpInternalCorner) ?? false
        cutDirection = try c.decodeIfPresent(ProfileCutDirection.self, forKey: .cutDirection) ?? .climb
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cutMode, forKey: .cutMode)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeFeedRateMmPerMin, forKey: .plungeFeedRateMmPerMin)
        try c.encode(maxDepthOfCutMm, forKey: .maxDepthOfCutMm)
        try c.encode(toolDiameterMm, forKey: .toolDiameterMm)
        try c.encode(tabWidths, forKey: .tabWidths)
        try c.encode(finishPasses, forKey: .finishPasses)
        try c.encode(leadInDistanceMm, forKey: .leadInDistanceMm)
        try c.encode(leadOutDistanceMm, forKey: .leadOutDistanceMm)
        try c.encode(spindleRpm, forKey: .spindleRpm)
        try c.encode(addTabs, forKey: .addTabs)
        try c.encode(tabLengthMm, forKey: .tabLengthMm)
        try c.encode(tabThicknessMm, forKey: .tabThicknessMm)
        try c.encode(tabSpacingMm, forKey: .tabSpacingMm)
        try c.encode(use3DTabs, forKey: .use3DTabs)
        try c.encode(rampType, forKey: .rampType)
        try c.encode(rampDistanceMm, forKey: .rampDistanceMm)
        try c.encode(leadInType, forKey: .leadInType)
        try c.encode(leadInAngleDegrees, forKey: .leadInAngleDegrees)
        try c.encode(circularLeadRadiusMm, forKey: .circularLeadRadiusMm)
        try c.encode(doLeadOut, forKey: .doLeadOut)
        try c.encode(sharpExternalCorner, forKey: .sharpExternalCorner)
        try c.encode(sharpInternalCorner, forKey: .sharpInternalCorner)
        try c.encode(cutDirection, forKey: .cutDirection)
    }
}

// MARK: - Profile Toolpath Result

/// Represents the computed profile toolpath with G-code segments and metadata.
public struct ProfileToolpathResult: Codable, Sendable {
    
    public let params: ProfileToolpathParams
    public let material: Material?
    public let gcodeLines: [String]
    public let estimatedTimeSeconds: Double
    public let passCount: Int
    public let path: [String]
    
    /// Whether tabs were added to the toolpath.
    public var hasTabs: Bool { !params.tabWidths.isEmpty }
    
    /// Bounding box of the toolpath in mm.
    public let boundsMinX: Double?
    public let boundsMinY: Double?
    public let boundsMaxX: Double?
    public let boundsMaxY: Double?
}

// MARK: - Profile Toolpath Engine

/// Computes profile toolpaths from vector paths with offset calculation based on cut mode and tool diameter.
public struct ProfileToolpathEngine {
    
    /// Compute a profile toolpath for the given vectors and parameters.
    public static func compute(
        vectors: [VectorPath],
        params: ProfileToolpathParams,
        material: Material? = nil,
        stockHeightMm: Double = 25.0
    ) -> ProfileToolpathResult {
        
        var allGcodeLines: [String] = []
        var allPathSegments: [String] = []
        let feedRate = params.feedRateMmPerMin
        let plungeFeed = params.plungeFeedRateMmPerMin
        
        // Generate G-code header
        allGcodeLines.append("%")
        allGcodeLines.append("O=PROFILE_TOOLPATH")
        allGcodeLines.append("(Tool: \(Int(params.toolDiameterMm * 10))mm)")
        // SPK-1133b — linked spindle RPM from the assigned tool's cut data.
        if params.spindleRpm > 0 {
            allGcodeLines.append("M3 S\(Int(params.spindleRpm))")
        }
        
        var totalLength = 0.0
        var maxPassCount = 0
        
        for vector in vectors {
            guard !vector.points.isEmpty else { continue }
            
            // Calculate offset based on cut mode and tool diameter
            let toolRadius = params.toolDiameterMm / 2.0
            let offsetDistance: Double
            
            switch params.cutMode {
            case .outCut:
                offsetDistance = toolRadius
            case .inCut:
                offsetDistance = -toolRadius
            case .onCut:
                offsetDistance = 0
            }
            
            // For closed polylines, use proper perpendicular offset
            let offsetPoints: [VectorPoint]
            if vector.isClosed && vector.points.count >= 3 {
                if let result = offsetClosedPolyline(points: vector.points, by: offsetDistance) {
                    offsetPoints = result
                } else {
                    // Fallback to naive offset
                    offsetPoints = vector.points.map { VectorPoint(x: $0.x + offsetDistance, y: $0.y) }
                }
            } else {
                // Open polylines: simple axis-aligned offset
                offsetPoints = vector.points.map { VectorPoint(x: $0.x + offsetDistance, y: $0.y + offsetDistance) }
            }
            
            // Calculate depth passes
            let passCount = Int(ceil(stockHeightMm / params.maxDepthOfCutMm))
            maxPassCount = max(maxPassCount, passCount)
            
            for pass in 1...passCount {
                let zDepth = -Double(pass) * params.maxDepthOfCutMm
                
                // Add G-code for this pass
                allGcodeLines.append("")
                allGcodeLines.append("(Pass \(pass)/\(passCount), Z=\(String(format: "%.3f", zDepth)))")
                
                // Rapid to safe height
                allGcodeLines.append("G0 Z5.0")
                
                // Move to start point with lead-in
                if let startPoint = offsetPoints.first {
                    let leadInX = startPoint.x - params.leadInDistanceMm
                    allGcodeLines.append("G0 X\(String(format: "%.3f", leadInX)) Y\(String(format: "%.3f", startPoint.y))")
                    allGcodeLines.append("G1 Z\(String(format: "%.3f", zDepth)) F\(Int(plungeFeed))")
                    
                    // Move to start with lead-in
                    allGcodeLines.append("G1 X\(String(format: "%.3f", startPoint.x)) Y\(String(format: "%.3f", startPoint.y)) F\(Int(feedRate))")
                    allPathSegments.append("G1 X\(String(format: "%.3f", startPoint.x)) Y\(String(format: "%.3f", startPoint.y)) F\(Int(feedRate))")
                }
                
                // Follow the offset path
                for i in 1..<offsetPoints.count {
                    let point = offsetPoints[i]
                    allGcodeLines.append("G1 X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y)) F\(Int(feedRate))")
                    allPathSegments.append("G1 X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y)) F\(Int(feedRate))")
                }
                
                // Close the path if vector is closed
                if vector.isClosed && offsetPoints.count > 2 {
                    let firstPoint = offsetPoints.first!
                    allGcodeLines.append("G1 X\(String(format: "%.3f", firstPoint.x)) Y\(String(format: "%.3f", firstPoint.y)) F\(Int(feedRate))")
                    allPathSegments.append("G1 X\(String(format: "%.3f", firstPoint.x)) Y\(String(format: "%.3f", firstPoint.y)) F\(Int(feedRate))")
                }
                
                // Lead-out at end point
                if let endPoint = offsetPoints.last {
                    let leadOutX = endPoint.x + params.leadOutDistanceMm
                    allGcodeLines.append("G1 X\(String(format: "%.3f", leadOutX)) Y\(String(format: "%.3f", endPoint.y)) F\(Int(feedRate))")
                    allPathSegments.append("G1 X\(String(format: "%.3f", leadOutX)) Y\(String(format: "%.3f", endPoint.y)) F\(Int(feedRate))")
                }
                
                // Rapid to safe height
                allGcodeLines.append("G0 Z5.0")
            }
            
            totalLength += vector.length
        }
        
        // Add G-code footer
        allGcodeLines.append("")
        allGcodeLines.append("M30")
        allGcodeLines.append("%")
        
        // Calculate estimated time (rough approximation)
        let cuttingTime = totalLength * Double(maxPassCount) / feedRate * 60.0
        
        return ProfileToolpathResult(
            params: params,
            material: material,
            gcodeLines: allGcodeLines,
            estimatedTimeSeconds: cuttingTime,
            passCount: maxPassCount,
            path: allPathSegments,
            boundsMinX: nil,
            boundsMinY: nil,
            boundsMaxX: nil,
            boundsMaxY: nil
        )
    }
    
    /// Calculate the offset direction based on cut mode and tool diameter.
    private static func calculateOffset(for mode: ProfileCutMode, toolRadius: Double) -> (dx: Double, dy: Double) {
        switch mode {
        case .outCut: return (toolRadius, -toolRadius) // Offset outward
        case .inCut: return (-toolRadius, toolRadius)   // Offset inward
        case .onCut: return (0, 0)                       // No offset
        }
    }
    
    // MARK: - Perpendicular offset for closed polylines
    
    /// Offsets a closed polyline outward/inward by a signed distance using
    /// perpendicular-edge intersection (same algorithm as VectorOffsetCalculator.offsetClosedPolyline).
    private static func offsetClosedPolyline(points: [VectorPoint], by distance: Double) -> [VectorPoint]? {
        guard points.count >= 3 else { return nil }

        // Normalize: an explicit closing duplicate (first == last) is dropped so
        // each corner is processed exactly once. Without this, the modulo wrap
        // makes prev == curr at index 0 (zero-length edge), the start/end corner
        // is skipped, and a closed rect profile misses one corner and closes the
        // loop with a diagonal across the part interior (SPK-0600 E2E-caught;
        // mirrors the fix already in VectorOffset.offsetClosedPolyline).
        var pts = points
        if pts.count > 1, pts.first == pts.last {
            pts.removeLast()
        }
        guard pts.count >= 3 else { return nil }

        var offsetVerts: [VectorPoint] = []
        for i in 0..<pts.count {
            let curr = pts[i]
            let prev = pts[(i - 1 + pts.count) % pts.count]
            let next = pts[(i + 1) % pts.count]
            
            let dx1 = curr.x - prev.x
            let dy1 = curr.y - prev.y
            let len1 = sqrt(dx1 * dx1 + dy1 * dy1)
            
            let dx2 = next.x - curr.x
            let dy2 = next.y - curr.y
            let len2 = sqrt(dx2 * dx2 + dy2 * dy2)
            
            guard len1 > 1e-9, len2 > 1e-9 else { continue }
            
            let nx1 = -dy1 / len1
            let ny1 = dx1 / len1
            let nx2 = -dy2 / len2
            let ny2 = dx2 / len2
            
            let nx = (nx1 + nx2) / 2.0
            let ny = (ny1 + ny2) / 2.0
            let nLen = sqrt(nx * nx + ny * ny)
            guard nLen > 1e-9 else { continue }
            
            offsetVerts.append(VectorPoint(
                x: curr.x + nx / nLen * distance,
                y: curr.y + ny / nLen * distance
            ))
        }
        
        guard !offsetVerts.isEmpty else { return nil }
        
        var offsetPath: [VectorPoint] = []
        for i in 0..<offsetVerts.count {
            let curr = offsetVerts[i]
            let next = offsetVerts[(i + 1) % offsetVerts.count]
            let prev = offsetVerts[(i - 1 + offsetVerts.count) % offsetVerts.count]
            
            let e1dx = curr.x - prev.x
            let e1dy = curr.y - prev.y
            let e2dx = next.x - curr.x
            let e2dy = next.y - curr.y
            
            if let intersection = lineIntersection(
                p1: prev, d1: (e1dx, e1dy),
                p2: curr, d2: (e2dx, e2dy)
            ) {
                offsetPath.append(intersection)
            }
        }
        
        if offsetPath.isEmpty {
            offsetPath = offsetVerts
        }
        
        if let first = offsetPath.first, offsetPath.last != first {
            offsetPath.append(first)
        }
        
        return offsetPath
    }
    
    /// Find intersection point of two lines defined by point + direction.
    private static func lineIntersection(
        p1: VectorPoint, d1: (Double, Double),
        p2: VectorPoint, d2: (Double, Double)
    ) -> VectorPoint? {
        let (d1x, d1y) = d1
        let (d2x, d2y) = d2
        let denom = d1x * d2y - d1y * d2x
        guard abs(denom) > 1e-12 else { return nil }
        
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        
        let t = (dx * d2y - dy * d2x) / denom
        return VectorPoint(x: p1.x + t * d1x, y: p1.y + t * d1y)
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct ProfileToolpath_Previews: PreviewProvider {
    static var previews: some View {
        Text("Profile toolpath is a non-visual component")
    }
}
#endif

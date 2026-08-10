import Foundation

// MARK: - Vector Validator Expanded

// Validation category.
public enum ValidationCategory: String, Codable, Sendable {
    case topology
    case geometry
    case precision
    case performance
}

// Vector geometry validation error type.
public enum VectorValidationError: String, Codable, Sendable {
    case openPath
    case selfIntersection
    case degenerate
    case duplicateNode
    case zeroLength
    case overlappingSegments
    case nonManifold
    case invalidArc
    case nestedContours
    case unclosedPath
}

// Vector geometry validation warning type.
public enum VectorValidationWarning: String, Codable, Sendable {
    case nearSelfIntersection
    case nearZeroLength
    case sharpCorner
    case redundantNode
    case nearColinear
    case largeGap
    case potentialOverlap
}

// Fix action type.
public enum VectorFixActionType: String, Codable, Sendable {
    case closePath
    case removeDuplicateNodes
    case splitIntersection
    case trimOverlap
    case removeSharpCorners
    case mergeSegments
    case simplifyPath
    case resamplePath
}

// Fix action.
public struct VectorFixAction: Codable, Sendable {
    public let id: UUID
    public let description: String
    public let action: VectorFixActionType
    public let targetShapeId: UUID?
    public let confidence: Double
    public let estimatedImpact: String
    
    public init(
        id: UUID = UUID(),
        description: String,
        action: VectorFixActionType,
        targetShapeId: UUID? = nil,
        confidence: Double = 1.0,
        estimatedImpact: String = "Medium"
    ) {
        self.id = id
        self.description = description
        self.action = action
        self.targetShapeId = targetShapeId
        self.confidence = max(0.0, min(1.0, confidence))
        self.estimatedImpact = estimatedImpact
    }
}

// Validation result for a single shape.
public struct VectorValidationResult: Codable, Sendable {
    public let shapeId: UUID
    public var isValid: Bool
    public var errors: [VectorValidationError]
    public var warnings: [VectorValidationWarning]
    public var fixActions: [VectorFixAction]
    public var pointCount: Int
    public var totalLength: Double
    public var boundingBox: BoundingBox3D
    public var category: ValidationCategory
    
    public init(
        shapeId: UUID,
        isValid: Bool,
        errors: [VectorValidationError] = [],
        warnings: [VectorValidationWarning] = [],
        fixActions: [VectorFixAction] = [],
        pointCount: Int = 0,
        totalLength: Double = 0.0,
        boundingBox: BoundingBox3D = BoundingBox3D(),
        category: ValidationCategory = .topology
    ) {
        self.shapeId = shapeId
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
        self.fixActions = fixActions
        self.pointCount = pointCount
        self.totalLength = totalLength
        self.boundingBox = boundingBox
        self.category = category
    }
}

// Batch validation result.
public struct BatchVectorValidationResult: Codable, Sendable {
    public var totalShapes: Int
    public var validShapes: Int
    public var invalidShapes: Int
    public var results: [VectorValidationResult]
    public var totalErrors: Int
    public var totalWarnings: Int
    public var criticalErrors: [VectorValidationResult]
    public var summary: String
    
    public init(
        totalShapes: Int,
        validShapes: Int,
        invalidShapes: Int,
        results: [VectorValidationResult],
        totalErrors: Int,
        totalWarnings: Int,
        criticalErrors: [VectorValidationResult],
        summary: String
    ) {
        self.totalShapes = totalShapes
        self.validShapes = validShapes
        self.invalidShapes = invalidShapes
        self.results = results
        self.totalErrors = totalErrors
        self.totalWarnings = totalWarnings
        self.criticalErrors = criticalErrors
        self.summary = summary
    }
}

// Validation threshold configuration.
public struct VectorValidationThresholds: Codable, Sendable {
    public var nearIntersectionThreshold: Double
    public var nearZeroLengthThreshold: Double
    public var sharpCornerAngle: Double
    public var redundantNodeThreshold: Double
    public var nearColinearThreshold: Double
    public var largeGapThreshold: Double
    public var potentialOverlapThreshold: Double
    
    public init(
        nearIntersectionThreshold: Double = 0.1,
        nearZeroLengthThreshold: Double = 0.01,
        sharpCornerAngle: Double = 15.0,
        redundantNodeThreshold: Double = 0.001,
        nearColinearThreshold: Double = 2.0,
        largeGapThreshold: Double = 1.0,
        potentialOverlapThreshold: Double = 0.05
    ) {
        self.nearIntersectionThreshold = max(0.0, nearIntersectionThreshold)
        self.nearZeroLengthThreshold = max(0.0, nearZeroLengthThreshold)
        self.sharpCornerAngle = max(0.0, min(180.0, sharpCornerAngle))
        self.redundantNodeThreshold = max(0.0, redundantNodeThreshold)
        self.nearColinearThreshold = max(0.0, nearColinearThreshold)
        self.largeGapThreshold = max(0.0, largeGapThreshold)
        self.potentialOverlapThreshold = max(0.0, potentialOverlapThreshold)
    }
}

// A vector shape represented as a list of points and segments.
public struct VectorShapeData: Codable, Sendable {
    public let id: UUID
    public let points: [VectorPoint]
    public let isClosed: Bool
    public let shapeType: VectorShapeType
    
    public init(
        id: UUID = UUID(),
        points: [VectorPoint],
        isClosed: Bool = false,
        shapeType: VectorShapeType = .freehand
    ) {
        self.id = id
        self.points = points
        self.isClosed = isClosed
        self.shapeType = shapeType
    }
}

// Shape type for validation.
public enum VectorShapeType: String, Codable, Sendable {
    case line
    case circle
    case rectangle
    case arc
    case ellipse
    case polygon
    case star
    case freehand
}

// MARK: - VectorValidator

// Comprehensive vector geometry validator.
public final class VectorValidator {
    
    // Default thresholds.
    public static let defaultThresholds = VectorValidationThresholds()
    
    // Validates a single shape.
    public static func validate(
        shapeData: VectorShapeData,
        thresholds: VectorValidationThresholds = defaultThresholds
    ) -> VectorValidationResult {
        var errors: [VectorValidationError] = []
        var warnings: [VectorValidationWarning] = []
        var fixActions: [VectorFixAction] = []
        
        let points = shapeData.points
        let pointCount = points.count
        
        // Calculate total length
        var totalLength = 0.0
        if points.count >= 2 {
            for i in 0..<(points.count - 1) {
                totalLength += distance(points[i], points[i+1])
            }
            if shapeData.isClosed && points.count >= 2 {
                totalLength += distance(points.last!, points.first!)
            }
        }
        
        // Calculate bounding box
        var boundingBox = BoundingBox3D()
        if !points.isEmpty {
            var minX = points[0].x, maxX = points[0].x
            var minY = points[0].y, maxY = points[0].y
            for p in points {
                minX = min(minX, p.x)
                maxX = max(maxX, p.x)
                minY = min(minY, p.y)
                maxY = max(maxY, p.y)
            }
            boundingBox = BoundingBox3D(minX: minX, minY: minY, minZ: 0, maxX: maxX, maxY: maxY, maxZ: 0)
        }
        
        // Check for degenerate shapes
        if pointCount < 2 {
            errors.append(.degenerate)
            // No implemented auto-fix for degenerate geometry yet.
        }
        
        // Check for zero-length segments
        let zeroLengthCount = points.enumerated().filter { i, p in
            if i == 0 { return false }
            return distance(points[i-1], p) < thresholds.nearZeroLengthThreshold
        }.count
        if zeroLengthCount > 0 {
            errors.append(.zeroLength)
            warnings.append(.nearZeroLength)
        }
        
        // Check for duplicate points
        let duplicates = findDuplicatePoints(points: points, threshold: thresholds.redundantNodeThreshold)
        if !duplicates.isEmpty {
            errors.append(.duplicateNode)
            warnings.append(.redundantNode)
            fixActions.append(VectorFixAction(
                description: "Remove \(duplicates.count) duplicate points",
                action: .removeDuplicateNodes,
                targetShapeId: shapeData.id,
                confidence: 0.95,
                estimatedImpact: "Medium"
            ))
        }
        
        // For closed shapes, check for self-intersections
        if shapeData.isClosed && points.count >= 4 {
            let intersections = findSelfIntersections(points: points)
            if !intersections.isEmpty {
                errors.append(.selfIntersection)
                // splitIntersection not implemented — surface error only.
            } else {
                let nearIntersections = findNearSelfIntersections(points: points, threshold: thresholds.nearIntersectionThreshold)
                if !nearIntersections.isEmpty {
                    warnings.append(.nearSelfIntersection)
                }
            }
            
            // Check for overlapping segments
            let overlaps = findOverlappingSegments(points: points, threshold: thresholds.potentialOverlapThreshold)
            if !overlaps.isEmpty {
                errors.append(.overlappingSegments)
                // trimOverlap not implemented — surface error only.
            }
            
            // Check for sharp corners
            let sharpCorners = findSharpCorners(points: points, angleThreshold: thresholds.sharpCornerAngle)
            if !sharpCorners.isEmpty {
                warnings.append(.sharpCorner)
                // removeSharpCorners not implemented — surface warning only.
            }
            
            // Check for near-colinear segments
            let colinear = findNearColinearSegments(points: points, threshold: thresholds.nearColinearThreshold)
            if !colinear.isEmpty {
                warnings.append(.nearColinear)
                // mergeSegments not implemented — surface warning only.
            }
        } else {
            // Open shapes: check for large gaps between points
            let gaps = findLargeGaps(points: points, threshold: thresholds.largeGapThreshold)
            if !gaps.isEmpty {
                warnings.append(.largeGap)
            }
            
            // Check for unclosed freehand paths
            if shapeData.shapeType == .freehand && points.count >= 3 {
                let first = points.first!
                let last = points.last!
                if distance(first, last) > thresholds.largeGapThreshold {
                    warnings.append(.nearSelfIntersection)
                }
            }
        }
        
        let isValid = errors.isEmpty
        
        return VectorValidationResult(
            shapeId: shapeData.id,
            isValid: isValid,
            errors: errors,
            warnings: warnings,
            fixActions: fixActions,
            pointCount: pointCount,
            totalLength: totalLength,
            boundingBox: boundingBox,
            category: errors.contains(.selfIntersection) || errors.contains(.overlappingSegments) ? .geometry : .topology
        )
    }
    
    // Validates multiple shapes.
    public static func validateBatch(
        shapes: [VectorShapeData],
        thresholds: VectorValidationThresholds = defaultThresholds
    ) -> BatchVectorValidationResult {
        var results: [VectorValidationResult] = []
        var totalErrors = 0
        var totalWarnings = 0
        var criticalErrors: [VectorValidationResult] = []
        
        for shape in shapes {
            let result = validate(shapeData: shape, thresholds: thresholds)
            results.append(result)
            totalErrors += result.errors.count
            totalWarnings += result.warnings.count
            if !result.errors.isEmpty {
                criticalErrors.append(result)
            }
        }
        
        let validShapes = results.filter { $0.isValid }.count
        let invalidShapes = results.filter { !$0.isValid }.count
        
        let summary = "Validated \(results.count) shapes: \(validShapes) valid, \(invalidShapes) invalid, \(totalErrors) errors, \(totalWarnings) warnings"
        
        return BatchVectorValidationResult(
            totalShapes: results.count,
            validShapes: validShapes,
            invalidShapes: invalidShapes,
            results: results,
            totalErrors: totalErrors,
            totalWarnings: totalWarnings,
            criticalErrors: criticalErrors,
            summary: summary
        )
    }
    
    // Finds duplicate points.
    private static func findDuplicatePoints(points: [VectorPoint], threshold: Double) -> [VectorPoint] {
        var duplicates: [VectorPoint] = []
        for i in 0..<points.count {
            for j in (i+1)..<points.count {
                let dx = points[i].x - points[j].x
                let dy = points[i].y - points[j].y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < threshold {
                    duplicates.append(points[j])
                }
            }
        }
        return duplicates
    }
    
    // Finds self-intersections.
    private static func findSelfIntersections(points: [VectorPoint]) -> [(Int, Int)] {
        var intersections: [(Int, Int)] = []
        for i in 0..<points.count - 1 {
            for j in (i+2)..<points.count {
                let p1 = points[i], p2 = points[i+1]
                let p3 = points[j], p4 = j + 1 < points.count ? points[j+1] : points[0]
                if segmentsIntersect(p1, p2, p3, p4) {
                    intersections.append((i, j))
                }
            }
        }
        return intersections
    }
    
    // Checks if two segments intersect.
    private static func segmentsIntersect(_ p1: VectorPoint, _ p2: VectorPoint, _ p3: VectorPoint, _ p4: VectorPoint) -> Bool {
        let d1 = direction(p3, p4, p1)
        let d2 = direction(p3, p4, p2)
        let d3 = direction(p1, p2, p3)
        let d4 = direction(p1, p2, p4)
        
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }
        
        return false
    }
    
    // Direction of three points.
    private static func direction(_ p1: VectorPoint, _ p2: VectorPoint, _ p3: VectorPoint) -> Double {
        (p3.x - p1.x) * (p2.y - p1.y) - (p2.x - p1.x) * (p3.y - p1.y)
    }
    
    // Finds near self-intersections.
    private static func findNearSelfIntersections(points: [VectorPoint], threshold: Double) -> [(Int, Int)] {
        var results: [(Int, Int)] = []
        for i in 0..<points.count - 1 {
            for j in (i+2)..<points.count {
                let p1 = points[i], p2 = points[i+1]
                let p3 = points[j], p4 = j + 1 < points.count ? points[j+1] : points[0]
                let dist = minDistanceBetweenSegments(p1, p2, p3, p4)
                if dist < threshold && dist > 0.001 {
                    results.append((i, j))
                }
            }
        }
        return results
    }
    
    // Minimum distance between two segments.
    private static func minDistanceBetweenSegments(_ p1: VectorPoint, _ p2: VectorPoint, _ p3: VectorPoint, _ p4: VectorPoint) -> Double {
        let d1 = distance(p1, p3)
        let d2 = distance(p1, p4)
        let d3 = distance(p2, p3)
        let d4 = distance(p2, p4)
        return min(d1, d2, d3, d4)
    }
    
    // Distance between two points.
    private static func distance(_ p1: VectorPoint, _ p2: VectorPoint) -> Double {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // Finds overlapping segments.
    private static func findOverlappingSegments(points: [VectorPoint], threshold: Double) -> [(Int, Int)] {
        var overlaps: [(Int, Int)] = []
        for i in 0..<points.count - 1 {
            for j in (i+1)..<points.count - 1 {
                let p1 = points[i], p2 = points[i+1]
                let p3 = points[j], p4 = points[j+1]
                let overlap = segmentOverlap(p1, p2, p3, p4)
                if overlap > threshold {
                    overlaps.append((i, j))
                }
            }
        }
        return overlaps
    }
    
    // Calculates overlap between two segments.
    //
    // Real segment-overlap test (SPK-0806 verify-caught): the previous
    // heuristic compared start-to-start distance against the longer segment
    // length, which flagged PERPENDICULAR segments as overlapping (a clean
    // closed square failed validation). The correct test: segments overlap
    // only when they are (nearly) collinear AND their projections onto the
    // shared axis overlap. Returns the overlap fraction of the shorter
    // segment, or 0 when not collinear / no overlap.
    private static func segmentOverlap(_ p1: VectorPoint, _ p2: VectorPoint, _ p3: VectorPoint, _ p4: VectorPoint) -> Double {
        let ax = p2.x - p1.x
        let ay = p2.y - p1.y
        let lenA = sqrt(ax * ax + ay * ay)
        guard lenA > 1e-9 else { return 0 }

        // Cross products measure how far C and D sit from line AB (collinearity).
        let crossC = abs((p3.x - p1.x) * ay - (p3.y - p1.y) * ax) / lenA
        let crossD = abs((p4.x - p1.x) * ay - (p4.y - p1.y) * ax) / lenA
        let collinearTolerance = 0.01 * lenA
        guard crossC < collinearTolerance && crossD < collinearTolerance else { return 0 }

        // Project C and D onto the AB axis.
        let tC = ((p3.x - p1.x) * ax + (p3.y - p1.y) * ay) / lenA
        let tD = ((p4.x - p1.x) * ax + (p4.y - p1.y) * ay) / lenA
        let t0: Double = 0
        let t1 = lenA

        // Overlap interval on the shared axis.
        let lo = max(min(tC, tD), t0)
        let hi = min(max(tC, tD), t1)
        let overlapLength = max(0, hi - lo)

        // Adjacent segments sharing exactly one endpoint have zero-length
        // overlap (touching, not overlapping).
        if overlapLength <= 1e-9 { return 0 }

        let lenB = distance(p3, p4)
        let shorter = max(1e-9, min(lenA, lenB))
        return overlapLength / shorter
    }
    
    // Finds sharp corners.
    private static func findSharpCorners(points: [VectorPoint], angleThreshold: Double) -> [VectorPoint] {
        var sharpCorners: [VectorPoint] = []
        
        for i in 1..<points.count - 1 {
            let prev = points[i-1]
            let curr = points[i]
            let next = points[i+1]
            
            let v1x = curr.x - prev.x
            let v1y = curr.y - prev.y
            let v2x = next.x - curr.x
            let v2y = next.y - curr.y
            
            let dot = v1x * v2x + v1y * v2y
            let mag1 = sqrt(v1x*v1x + v1y*v1y)
            let mag2 = sqrt(v2x*v2x + v2y*v2y)
            
            if mag1 > 0 && mag2 > 0 {
                let cosAngle = dot / (mag1 * mag2)
                let clamped = max(-1.0, min(1.0, cosAngle))
                let angle = acos(clamped) * 180.0 / .pi
                
                if angle < angleThreshold {
                    sharpCorners.append(curr)
                }
            }
        }
        
        return sharpCorners
    }
    
    // Finds near-colinear segments.
    private static func findNearColinearSegments(points: [VectorPoint], threshold: Double) -> [(Int, Int)] {
        var colinear: [(Int, Int)] = []
        
        for i in 0..<points.count - 1 {
            for j in (i+1)..<points.count - 1 {
                let p1 = points[i], p2 = points[i+1]
                let p3 = points[j], p4 = points[j+1]
                let angle = segmentAngle(p1, p2, p3, p4)
                if angle < threshold {
                    colinear.append((i, j))
                }
            }
        }
        
        return colinear
    }
    
    // Gets angle between two segments.
    private static func segmentAngle(_ p1: VectorPoint, _ p2: VectorPoint, _ p3: VectorPoint, _ p4: VectorPoint) -> Double {
        let v1x = p2.x - p1.x
        let v1y = p2.y - p1.y
        let v2x = p4.x - p3.x
        let v2y = p4.y - p3.y
        
        let dot = v1x * v2x + v1y * v2y
        let mag1 = sqrt(v1x*v1x + v1y*v1y)
        let mag2 = sqrt(v2x*v2x + v2y*v2y)
        
        if mag1 > 0 && mag2 > 0 {
            let cosAngle = dot / (mag1 * mag2)
            let clamped = max(-1.0, min(1.0, cosAngle))
            return acos(clamped) * 180.0 / .pi
        }
        
        return 0
    }
    
    // Finds large gaps.
    private static func findLargeGaps(points: [VectorPoint], threshold: Double) -> [VectorPoint] {
        var gaps: [VectorPoint] = []
        
        for i in 0..<points.count - 1 {
            let dist = distance(points[i], points[i+1])
            if dist > threshold {
                gaps.append(points[i+1])
            }
        }
        
        return gaps
    }
    
    // Applies a fix action to a shape.
    public static func applyFix(
        action: VectorFixAction,
        points: inout [VectorPoint],
        isClosed: inout Bool
    ) -> Bool {
        switch action.action {
        case .closePath:
            return closePath(points: &points, isClosed: &isClosed)
        case .removeDuplicateNodes:
            return removeDuplicates(points: &points)
        case .splitIntersection, .trimOverlap, .removeSharpCorners,
             .mergeSegments, .simplifyPath, .resamplePath:
            // Not implemented — do not claim success for unimplemented fixes.
            return false
        }
    }
    
    // Closes an open path.
    private static func closePath(points: inout [VectorPoint], isClosed: inout Bool) -> Bool {
        guard let first = points.first, let last = points.last else { return false }
        if distance(first, last) > 0.001 {
            points.append(first)
        }
        isClosed = true
        return true
    }
    
    // Removes duplicate points.
    private static func removeDuplicates(points: inout [VectorPoint]) -> Bool {
        var unique: [VectorPoint] = []
        var seen: Set<String> = []
        for pt in points {
            let key = "\(pt.x)_\(pt.y)"
            if !seen.contains(key) {
                unique.append(pt)
                seen.insert(key)
            }
        }
        points = unique
        return true
    }
    
    // Validates thresholds.
    public static func validate(_ thresholds: VectorValidationThresholds) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if thresholds.nearIntersectionThreshold < 0 { errors.append("Near intersection threshold must be non-negative") }
        if thresholds.nearZeroLengthThreshold < 0 { errors.append("Near zero length threshold must be non-negative") }
        if thresholds.sharpCornerAngle < 0 || thresholds.sharpCornerAngle > 180 { errors.append("Sharp corner angle must be 0-180") }
        if thresholds.redundantNodeThreshold < 0 { errors.append("Redundant node threshold must be non-negative") }
        if thresholds.nearColinearThreshold < 0 { errors.append("Near colinear threshold must be non-negative") }
        if thresholds.largeGapThreshold < 0 { errors.append("Large gap threshold must be non-negative") }
        if thresholds.potentialOverlapThreshold < 0 { errors.append("Potential overlap threshold must be non-negative") }
        
        return (errors.isEmpty, errors)
    }
}

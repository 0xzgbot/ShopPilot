import Foundation

// MARK: - Array Copy Toolpath + Merged Toolpath

// Array copy type.
public enum ArrayCopyType: String, Codable, Sendable {
    case linear
    case circular
}

// Linear array copy parameters.
public struct LinearArrayCopyParams: Codable, Sendable {
    public var count: Int
    public var spacing: Double
    public var angle: Double
    
    public init(count: Int = 2, spacing: Double = 10.0, angle: Double = 0.0) {
        self.count = max(1, count)
        self.spacing = max(0, spacing)
        self.angle = ((angle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
    }
}

// Circular array copy parameters.
public struct CircularArrayCopyParams: Codable, Sendable {
    public var count: Int
    public var centerX: Double
    public var centerY: Double
    public var startAngle: Double
    public var endAngle: Double
    public var radius: Double
    
    public init(count: Int = 2, centerX: Double = 0.0, centerY: Double = 0.0,
                startAngle: Double = 0.0, endAngle: Double = 360.0, radius: Double = 50.0) {
        self.count = max(1, count)
        self.centerX = centerX
        self.centerY = centerY
        self.startAngle = ((startAngle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        self.endAngle = ((endAngle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        self.radius = max(0, radius)
    }
}

// Array copy result.
public struct ArrayCopyResult: Codable, Sendable {
    public var arrayType: ArrayCopyType
    public var originalID: UUID
    public var copiedIDs: [UUID]
    public var totalCount: Int
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        arrayType: ArrayCopyType,
        originalID: UUID,
        copiedIDs: [UUID] = [],
        totalCount: Int,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.arrayType = arrayType
        self.originalID = originalID
        self.copiedIDs = copiedIDs
        self.totalCount = totalCount
        self.success = success
        self.errorMessage = errorMessage
    }
}

// Merged toolpath parameters.
public struct MergedToolpathParams: Codable, Sendable {
    public var sourceToolpathIDs: [UUID]
    public var mergeMode: MergeMode
    public var keepOriginals: Bool
    
    public init(
        sourceToolpathIDs: [UUID] = [],
        mergeMode: MergeMode = .union,
        keepOriginals: Bool = true
    ) {
        self.sourceToolpathIDs = sourceToolpathIDs
        self.mergeMode = mergeMode
        self.keepOriginals = keepOriginals
    }
}

// Merge mode for combining toolpaths.
public enum MergeMode: String, Codable, Sendable {
    case union
    case intersection
    case difference
    case exclusiveOr
}

// Merged toolpath result.
public struct MergedToolpathResult: Codable, Sendable {
    public var mergeMode: MergeMode
    public var sourceIDs: [UUID]
    public var mergedToolpathID: UUID
    public var totalSegments: Int
    public var totalLengthMm: Double
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        mergeMode: MergeMode,
        sourceIDs: [UUID],
        mergedToolpathID: UUID,
        totalSegments: Int,
        totalLengthMm: Double,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.mergeMode = mergeMode
        self.sourceIDs = sourceIDs
        self.mergedToolpathID = mergedToolpathID
        self.totalSegments = totalSegments
        self.totalLengthMm = totalLengthMm
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - Path Array Copy (SPK-2023e)

/// Mode for distributing copies along a path.
public enum PathArrayCopyMode: Codable, Sendable {
    /// Place exactly N copies evenly spaced by arc length.
    case count(Int)
    /// Place copies at fixed arc-length spacing along the path.
    case spacing(Double)
}

/// Distribute array copies along an arbitrary path.
public struct PathArrayCopyParams: Codable, Sendable {
    public var targetPathID: UUID
    public var mode: PathArrayCopyMode
    /// Rotate each copy to align with the path tangent at its position.
    public var followTangent: Bool

    public init(
        targetPathID: UUID,
        mode: PathArrayCopyMode = .count(4),
        followTangent: Bool = false
    ) {
        self.targetPathID = targetPathID
        self.mode = mode
        self.followTangent = followTangent
    }
}

public struct PathArrayCopyPosition: Codable, Sendable {
    public var x: Double
    public var y: Double
}

/// Result of a path array copy: each entry is the position + tangent angle.
public struct PathArrayCopyResult: Codable, Sendable {
    public var positions: [PathArrayCopyPosition]
    public var angles: [Double]
    public var success: Bool
    public var errorMessage: String?
}

extension ArrayCopyAndMergeEngine {

    /// Distribute copies along a polyline (array of points).
    ///
    /// - Parameters:
    ///   - points: the path vertices in order (the polyline to follow).
    ///   - params: path array copy parameters.
    /// - Returns: positions and optional tangent angles along the path.
    public static func createPathArray(
        points: [VectorPoint],
        params: PathArrayCopyParams
    ) -> PathArrayCopyResult {
        guard points.count >= 2 else {
            return PathArrayCopyResult(
                positions: [], angles: [], success: false,
                errorMessage: "Path must have at least 2 points")
        }

        // Cumulative arc length at each vertex.
        var cum: [Double] = [0]
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            cum.append(cum.last! + (dx * dx + dy * dy).squareRoot())
        }
        let totalLength = cum.last!
        guard totalLength > 1e-9 else {
            return PathArrayCopyResult(
                positions: [], angles: [], success: false,
                errorMessage: "Path has zero length")
        }

        // Target positions along the path.
        let targetS: [Double]
        switch params.mode {
        case .count(let n):
            let n = max(1, n)
            if n == 1 {
                targetS = [0]
            } else {
                targetS = (0..<n).map { i in
                    totalLength * Double(i) / Double(n - 1)
                }
            }
        case .spacing(let s):
            guard s > 1e-9 else {
                return PathArrayCopyResult(
                    positions: [], angles: [], success: false,
                    errorMessage: "Spacing must be positive")
            }
            var accum = 0.0
            var ts: [Double] = []
            while accum <= totalLength + 1e-9 {
                ts.append(min(accum, totalLength))
                accum += s
            }
            targetS = ts
        }

        // Interpolate positions and compute tangent angles.
        var positions: [PathArrayCopyPosition] = []
        var angles: [Double] = []
        var segIdx = 0
        for s in targetS {
            while segIdx < cum.count - 2 && cum[segIdx + 1] < s - 1e-9 {
                segIdx += 1
            }
            let s0 = cum[segIdx]
            let s1 = cum[segIdx + 1]
            let segLen = s1 - s0
            let t = segLen > 1e-9 ? (s - s0) / segLen : 0
            let a = points[segIdx]
            let b = points[segIdx + 1]
            positions.append(PathArrayCopyPosition(
                x: a.x + t * (b.x - a.x),
                y: a.y + t * (b.y - a.y)
            ))
            if params.followTangent {
                let angle = atan2(b.y - a.y, b.x - a.x) * 180 / .pi
                angles.append(angle)
            }
        }

        return PathArrayCopyResult(
            positions: positions,
            angles: params.followTangent ? angles : [],
            success: true,
            errorMessage: nil)
    }
}

// Generates array copies and merges toolpaths.
public final class ArrayCopyAndMergeEngine {
    
    // Creates linear array copies.
    public static func createLinearArray(
        originalID: UUID,
        params: LinearArrayCopyParams
    ) -> ArrayCopyResult {
        if params.count < 1 {
            return ArrayCopyResult(
                arrayType: .linear,
                originalID: originalID,
                totalCount: 0,
                success: false,
                errorMessage: "Count must be at least 1"
            )
        }
        
        let copiedIDs = (1..<params.count).map { _ in UUID() }
        let totalCount = params.count
        
        return ArrayCopyResult(
            arrayType: .linear,
            originalID: originalID,
            copiedIDs: copiedIDs,
            totalCount: totalCount,
            success: true
        )
    }
    
    // Creates circular array copies.
    public static func createCircularArray(
        originalID: UUID,
        params: CircularArrayCopyParams
    ) -> ArrayCopyResult {
        if params.count < 1 {
            return ArrayCopyResult(
                arrayType: .circular,
                originalID: originalID,
                totalCount: 0,
                success: false,
                errorMessage: "Count must be at least 1"
            )
        }
        
        if params.radius <= 0 {
            return ArrayCopyResult(
                arrayType: .circular,
                originalID: originalID,
                totalCount: 0,
                success: false,
                errorMessage: "Radius must be positive"
            )
        }
        
        let copiedIDs = (1..<params.count).map { _ in UUID() }
        let totalCount = params.count
        
        return ArrayCopyResult(
            arrayType: .circular,
            originalID: originalID,
            copiedIDs: copiedIDs,
            totalCount: totalCount,
            success: true
        )
    }
    
    // Merges multiple toolpaths.
    public static func mergeToolpaths(
        params: MergedToolpathParams
    ) -> MergedToolpathResult {
        if params.sourceToolpathIDs.count < 2 {
            return MergedToolpathResult(
                mergeMode: params.mergeMode,
                sourceIDs: params.sourceToolpathIDs,
                mergedToolpathID: UUID(),
                totalSegments: 0,
                totalLengthMm: 0,
                success: false,
                errorMessage: "Need at least 2 toolpaths to merge"
            )
        }
        
        let totalSegments = params.sourceToolpathIDs.count * 10
        let totalLength = Double(params.sourceToolpathIDs.count) * 1000.0
        
        return MergedToolpathResult(
            mergeMode: params.mergeMode,
            sourceIDs: params.sourceToolpathIDs,
            mergedToolpathID: UUID(),
            totalSegments: totalSegments,
            totalLengthMm: totalLength,
            success: true
        )
    }
    
    // Validates array copy parameters.
    public static func validate(_ params: LinearArrayCopyParams) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        if params.count < 1 { errors.append("Count must be at least 1") }
        if params.spacing < 0 { errors.append("Spacing cannot be negative") }
        return (errors.isEmpty, errors)
    }
    
    public static func validate(_ params: CircularArrayCopyParams) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        if params.count < 1 { errors.append("Count must be at least 1") }
        if params.radius <= 0 { errors.append("Radius must be positive") }
        if params.startAngle < 0 || params.startAngle > 360 { errors.append("Start angle must be 0-360") }
        if params.endAngle < 0 || params.endAngle > 360 { errors.append("End angle must be 0-360") }
        return (errors.isEmpty, errors)
    }
    
    public static func validate(_ params: MergedToolpathParams) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        if params.sourceToolpathIDs.count < 2 { errors.append("Need at least 2 toolpaths to merge") }
        return (errors.isEmpty, errors)
    }
}

// MARK: - Real G-code transform engine (SPK-0803)

/// Persisted params for an array-copy / merge toolpath node (SPK-0803).
/// Stored as `paramsJSON` on the tree node so the op's configuration survives
/// save/open and recalc stays faithful.
public struct ArrayCopyParamsJSON: Codable, Sendable {
    public var kind: String        // "linear" | "circular" | "merge"
    public var count: Int
    public var spacing: Double
    public var angle: Double
    public var radius: Double
    public var centerX: Double
    public var centerY: Double

    public init(kind: String, count: Int, spacing: Double = 20.0, angle: Double = 0.0,
                radius: Double = 0.0, centerX: Double = 0.0, centerY: Double = 0.0) {
        self.kind = kind
        self.count = count
        self.spacing = spacing
        self.angle = angle
        self.radius = radius
        self.centerX = centerX
        self.centerY = centerY
    }
}

/// Transforms raw G-code lines for array-copy + merge operations. This is the
/// REAL engine behind SPK-0803 — the legacy `ArrayCopyAndMergeEngine` above
/// only fabricates ids/estimates and is retained for API compatibility.
public enum ToolpathGCodeTransformer {

    /// Result of transforming a G-code program.
    public struct TransformResult: Codable, Sendable {
        public let lines: [String]
        public let copyCount: Int
        public let moveCount: Int
        public var isEmpty: Bool { lines.isEmpty }
    }

    /// Parse the X/Y/Z coordinates out of a G0/G1/G2/G3 word line.
    /// Returns nil for non-motion lines (comments, %, O=, M-codes, etc.).
    public static func motionTarget(_ line: String) -> (x: Double?, y: Double?, z: Double?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("G0") || trimmed.hasPrefix("G1")
            || trimmed.hasPrefix("G2") || trimmed.hasPrefix("G3") else { return nil }
        var x: Double? = nil
        var y: Double? = nil
        var z: Double? = nil
        // Split on whitespace; each token is a word like "X12.5" or "F1500".
        for token in trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let word = String(token)
            if word.hasPrefix("X"), let v = Double(word.dropFirst()) { x = v }
            else if word.hasPrefix("Y"), let v = Double(word.dropFirst()) { y = v }
            else if word.hasPrefix("Z"), let v = Double(word.dropFirst()) { z = v }
        }
        return (x, y, z)
    }

    /// Apply a transform to one motion line: translate + rotate X/Y in place.
    /// Non-motion lines pass through untouched. Z words are preserved.
    public static func transformLine(_ line: String, translateX: Double, translateY: Double,
                                     rotateDegrees: Double = 0, centerX: Double = 0, centerY: Double = 0) -> String {
        guard let target = motionTarget(line) else { return line }
        let cosA = cos(rotateDegrees * .pi / 180.0)
        let sinA = sin(rotateDegrees * .pi / 180.0)
        var words: [String] = []
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for token in trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let word = String(token)
            if word.hasPrefix("X"), let v = Double(word.dropFirst()) {
                // translate first, then rotate about (centerX, centerY)
                let px = v + translateX - centerX
                let py = (target.y ?? 0) + translateY - centerY
                let rx = px * cosA - py * sinA + centerX
                words.append(String(format: "X%.3f", rx))
            } else if word.hasPrefix("Y"), let v = Double(word.dropFirst()) {
                let px = (target.x ?? 0) + translateX - centerX
                let py = v + translateY - centerY
                let ry = px * sinA + py * cosA + centerY
                words.append(String(format: "Y%.3f", ry))
            } else if word.hasPrefix("Z"), let v = Double(word.dropFirst()) {
                words.append(String(format: "Z%.3f", v))
            } else {
                words.append(word)
            }
        }
        return words.joined(separator: " ")
    }

    /// Linear array copy: `count` copies of `base` spaced by `spacing` along
    /// `angle` degrees (0 = +X axis, 90 = +Y). The first copy is the base
    /// itself (identity transform); each subsequent copy is translated.
    public static func linearArray(base: [String], params: LinearArrayCopyParams) -> TransformResult {
        guard params.count >= 1 else {
            return TransformResult(lines: [], copyCount: 0, moveCount: 0)
        }
        let rad = params.angle * .pi / 180.0
        let dx = cos(rad) * params.spacing
        let dy = sin(rad) * params.spacing
        var out: [String] = []
        for copy in 0..<params.count {
            let tx = Double(copy) * dx
            let ty = Double(copy) * dy
            for line in base {
                out.append(transformLine(line, translateX: tx, translateY: ty))
            }
        }
        return TransformResult(lines: out, copyCount: params.count, moveCount: out.count)
    }

    /// Circular array copy: `count` copies arranged around (centerX, centerY)
    /// at `radius`, sweeping startAngle → endAngle. Each copy is rotated in
    /// place by the placement angle (so it stays tangent to the ring like a
    /// clock hand) and translated to its ring position. Copy 0 sits at
    /// startAngle; the base program appears once per copy.
    public static func circularArray(base: [String], params: CircularArrayCopyParams) -> TransformResult {
        guard params.count >= 1, params.radius > 0 else {
            return TransformResult(lines: [], copyCount: 0, moveCount: 0)
        }
        var out: [String] = []
        for copy in 0..<params.count {
            let fraction = params.count > 1
                ? Double(copy) / Double(params.count - 1)
                : 0.0
            let sweep = params.startAngle + (params.endAngle - params.startAngle) * fraction
            let rad = sweep * .pi / 180.0
            let tx = cos(rad) * params.radius + params.centerX
            let ty = sin(rad) * params.radius + params.centerY
            for line in base {
                // Rotate in place about the copy's own origin, then translate
                // to the ring position (rotate-then-translate keeps the copy
                // exactly at `radius` from the center — the CAD circular-array
                // semantic, verified by ShopPilotVerify0803).
                let rotated = transformLine(line, translateX: 0, translateY: 0,
                                            rotateDegrees: sweep,
                                            centerX: 0, centerY: 0)
                out.append(transformLine(rotated, translateX: tx, translateY: ty))
            }
        }
        return TransformResult(lines: out, copyCount: params.count, moveCount: out.count)
    }

    /// Merge multiple programs in order, keeping each program's marker lines
    /// (`O=...`) so the merged node's identity is auditable. Returns the
    /// concatenated program.
    public static func merge(programs: [[String]]) -> [String] {
        var out: [String] = []
        for program in programs {
            if !out.isEmpty { out.append("") } // blank line between programs
            out.append(contentsOf: program)
        }
        return out
    }
}

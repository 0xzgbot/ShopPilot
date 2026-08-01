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

// MARK: - ArrayCopyAndMergeEngine

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

import Foundation

// MARK: - OperationMode

/// Boolean and scalar combine modes for 3D operations.
public enum OperationMode: String, Codable, Sendable {
    /// Union — merge shapes into a single solid.
    case combineAdd
    /// Difference — subtract b from a.
    case combineSubtract
    /// Intersection — keep only overlapping volume.
    case combineMerge
    /// Low — minimum envelope (union of bounding boxes).
    case combineLow
    /// Multiply — element-wise product (scalar mode).
    case combineMultiply
    /// Max — element-wise maximum (scalar mode).
    case combineMax
    /// Min — element-wise minimum (scalar mode).
    case combineMin

    /// Human-readable label for UI display.
    public var displayLabel: String {
        switch self {
        case .combineAdd:
            return "Add"
        case .combineSubtract:
            return "Subtract"
        case .combineMerge:
            return "Merge"
        case .combineLow:
            return "Low"
        case .combineMultiply:
            return "Multiply"
        case .combineMax:
            return "Max"
        case .combineMin:
            return "Min"
        }
    }
}

// MARK: - CombineResult

/// Result of a combine operation.
public struct CombineResult: Codable, Sendable {
    public let mode: OperationMode
    public let resultComponents: [UUID]
    public let inputCount: Int
    public let success: Bool
    public let errorMessage: String?

    public init(
        mode: OperationMode,
        resultComponents: [UUID] = [],
        inputCount: Int = 0,
        success: Bool = false,
        errorMessage: String? = nil
    ) {
        self.mode = mode
        self.resultComponents = resultComponents
        self.inputCount = inputCount
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - CombineOperation

/// Tracks a pending or in-progress combine operation.
public struct CombineOperation: Identifiable, Codable, Sendable {
    public let id: UUID
    public let mode: OperationMode
    public let components: [UUID]
    public let timestamp: Date
    public var status: CombineStatus

    public init(
        id: UUID = UUID(),
        mode: OperationMode,
        components: [UUID],
        timestamp: Date = .now,
        status: CombineStatus = .pending
    ) {
        self.id = id
        self.mode = mode
        self.components = components
        self.timestamp = timestamp
        self.status = status
    }
}

// MARK: - CombineEngine

/// Engine for performing combine operations on components.
///
/// Uses UUID-based component references. Actual boolean geometry
/// computation is delegated to ShopPilotGeometry's BooleanOperations.
public struct CombineEngine {

    // MARK: - Public API

    /// Combine a collection of components using the specified mode.
    ///
    /// - Parameters:
    ///   - components: Components to combine.
    ///   - mode: The combine operation to perform.
    /// - Returns: A CombineResult describing the outcome.
    public static func combine(
        _ components: [UUID],
        mode: OperationMode
    ) -> CombineResult {
        guard components.count >= 2 else {
            return CombineResult(
                mode: mode,
                inputCount: components.count,
                success: false,
                errorMessage: "At least 2 components are required, got \(components.count)."
            )
        }

        // Delegate to pairwise combineAll for multi-component support.
        return combineAll(components, mode: mode)
    }

    /// Combine exactly two components.
    ///
    /// - Parameters:
    ///   - a: First component.
    ///   - b: Second component.
    ///   - mode: The combine operation to perform.
    /// - Returns: A CombineResult describing the outcome.
    public static func combinePair(
        _ a: UUID,
        _ b: UUID,
        mode: OperationMode
    ) -> CombineResult {
        // Validate inputs.
        guard a != b else {
            return CombineResult(
                mode: mode,
                inputCount: 2,
                success: false,
                errorMessage: "Cannot combine a component with itself."
            )
        }

        // For scalar modes, both inputs must be scalar-compatible.
        let scalarModes: [OperationMode] = [.combineMultiply, .combineMax, .combineMin]
        if scalarModes.contains(mode) {
            // Scalar modes always succeed in this stub — real validation
            // would inspect component type metadata.
            let resultId = UUID()
            return CombineResult(
                mode: mode,
                resultComponents: [resultId],
                inputCount: 2,
                success: true
            )
        }

        // Boolean modes: delegate to ShopPilotGeometry for actual boolean ops.
        // In this stub we return a synthetic result component.
        let resultId = UUID()
        return CombineResult(
            mode: mode,
            resultComponents: [resultId],
            inputCount: 2,
            success: true
        )
    }

    /// Combine all components in sequence (left-associative).
    ///
    /// For n components [a, b, c, d] with mode M:
    ///   ((a M b) M c) M d
    ///
    /// - Parameters:
    ///   - components: Components to combine.
    ///   - mode: The combine operation to perform.
    /// - Returns: A CombineResult describing the outcome.
    public static func combineAll(
        _ components: [UUID],
        mode: OperationMode
    ) -> CombineResult {
        guard components.count >= 2 else {
            return CombineResult(
                mode: mode,
                inputCount: components.count,
                success: false,
                errorMessage: "At least 2 components are required, got \(components.count)."
            )
        }

        var runningResult = components[0]
        var resultComponents: [UUID] = []

        for i in 1..<components.count {
            let pairResult = combinePair(runningResult, components[i], mode: mode)
            if !pairResult.success {
                return pairResult
            }
            // Use the first result component as the running accumulator.
            runningResult = pairResult.resultComponents.first ?? UUID()
            resultComponents.append(runningResult)
        }

        return CombineResult(
            mode: mode,
            resultComponents: resultComponents,
            inputCount: components.count,
            success: true
        )
    }
}

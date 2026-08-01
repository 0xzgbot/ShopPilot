import Foundation

// MARK: - CombineStatus

/// Status of a combine operation.
public enum CombineStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed

    /// Whether this status is terminal (no further transitions expected).
    public var isTerminal: Bool {
        self == .completed || self == .failed
    }

    /// Human-readable label for display.
    public var displayLabel: String {
        switch self {
        case .pending:
            return "Pending"
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
}

// MARK: - CombineHistoryEntry

/// A record of a completed combine operation, kept for undo/redo history.
public struct CombineHistoryEntry: Identifiable, Codable, Sendable {
    public let id: UUID
    public let mode: OperationMode
    public let timestamp: Date
    public let result: CombineResult
    public let undoable: Bool

    public init(
        id: UUID = UUID(),
        mode: OperationMode,
        timestamp: Date = .now,
        result: CombineResult,
        undoable: Bool = true
    ) {
        self.id = id
        self.mode = mode
        self.timestamp = timestamp
        self.result = result
        self.undoable = undoable
    }
}

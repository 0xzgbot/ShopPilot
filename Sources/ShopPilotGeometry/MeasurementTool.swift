import Foundation

// MARK: - Measurement Result

/// Represents a measurement between two points.
public struct MeasurementResult: Identifiable, Codable {
    public let id: UUID
    public let startPoint: VectorPoint
    public let endPoint: VectorPoint
    
    /// Euclidean distance between the two points.
    public var distance: Double {
        hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
    }
    
    /// Angle from start to end in radians (0 = right, π/2 = down).
    public var angleRadians: Double {
        atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
    }
    
    /// Angle from start to end in degrees.
    public var angleDegrees: Double {
        angleRadians * 180.0 / .pi
    }
    
    /// Delta X between the two points.
    public var deltaX: Double { endPoint.x - startPoint.x }
    
    /// Delta Y between the two points.
    public var deltaY: Double { endPoint.y - startPoint.y }
    
    /// Horizontal distance (absolute).
    public var horizontalDistance: Double { abs(deltaX) }
    
    /// Vertical distance (absolute).
    public var verticalDistance: Double { abs(deltaY) }
    
    public init(id: UUID = UUID(), startPoint: VectorPoint, endPoint: VectorPoint) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}

// MARK: - Measurement Tool State

/// Tracks the state of an active measurement tool.
public final class MeasurementToolState: ObservableObject {
    
    @Published public private(set) var measurements: [MeasurementResult] = []
    @Published public var startPoint: VectorPoint?
    @Published public var endPoint: VectorPoint?
    @Published public var isActive: Bool = false
    
    /// Begin a new measurement by setting the start point.
    public func beginMeasurement(at point: VectorPoint) {
        startPoint = point
        endPoint = nil
        isActive = true
    }
    
    /// Complete the current measurement by setting the end point.
    public func completeMeasurement(at point: VectorPoint) {
        guard let start = startPoint else { return }
        let result = MeasurementResult(startPoint: start, endPoint: point)
        measurements.append(result)
        endPoint = point
    }
    
    /// Cancel the current measurement and clear state.
    public func cancelMeasurement() {
        startPoint = nil
        endPoint = nil
        isActive = false
    }
    
    /// Clear all measurements.
    public func clearAllMeasurements() {
        measurements.removeAll()
        cancelMeasurement()
    }
    
    /// Get the current active measurement (in-progress or last completed).
    public var currentResult: MeasurementResult? {
        guard let start = startPoint, let end = endPoint else { return nil }
        return MeasurementResult(startPoint: start, endPoint: end)
    }
}

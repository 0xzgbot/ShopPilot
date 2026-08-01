import Foundation

// MARK: - Array Copy Toolpath

/// A toolpath created by array copying a base toolpath.
public struct ArrayCopyToolpath: Codable, Sendable {

    public let id: UUID
    public var name: String
    public let baseToolpathID: UUID
    public let pattern: ArrayCopyPattern
    public var toolID: UUID?
    public var feedRate: Double
    public var spindleSpeed: Double
    public var cutDepth: Double
    public var safeZ: Double
    public var completed: Bool
    public var generatedPaths: [GeneratedPath]

    public init(
        id: UUID = UUID(),
        name: String,
        baseToolpathID: UUID,
        pattern: ArrayCopyPattern,
        toolID: UUID? = nil,
        feedRate: Double = 1000,
        spindleSpeed: Double = 12000,
        cutDepth: Double = 1.0,
        safeZ: Double = 5.0,
        completed: Bool = false,
        generatedPaths: [GeneratedPath] = []
    ) {
        self.id = id
        self.name = name
        self.baseToolpathID = baseToolpathID
        self.pattern = pattern
        self.toolID = toolID
        self.feedRate = feedRate
        self.spindleSpeed = spindleSpeed
        self.cutDepth = cutDepth
        self.safeZ = safeZ
        self.completed = completed
        self.generatedPaths = generatedPaths
    }
}

// MARK: - Array Copy Pattern

public enum ArrayCopyPattern: Codable, Sendable {
    case linear(LinearPattern)
    case circular(CircularPattern)
    case none

    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .circular: return "Circular"
        case .none: return "Single"
        }
    }
}

// MARK: - Linear Pattern

/// Linear array copy pattern parameters.
public struct LinearPattern: Codable, Sendable {

    public var count: Int
    public var spacing: Double
    public var angle: Double

    public init(count: Int = 2, spacing: Double = 10.0, angle: Double = 0.0) {
        self.count = max(1, count)
        self.spacing = max(0, spacing)
        self.angle = ((angle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - Circular Pattern

/// Circular array copy pattern parameters.
public struct CircularPattern: Codable, Sendable {

    public var count: Int
    public var centerX: Double
    public var centerY: Double
    public var startAngle: Double
    public var endAngle: Double
    public var radius: Double

    public init(
        count: Int = 8,
        centerX: Double = 0.0,
        centerY: Double = 0.0,
        startAngle: Double = 0.0,
        endAngle: Double = 360.0,
        radius: Double = 25.0
    ) {
        self.count = max(1, count)
        self.centerX = centerX
        self.centerY = centerY
        self.startAngle = ((startAngle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        self.endAngle = ((endAngle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        self.radius = max(0, radius)
    }
}

// MARK: - Generated Path

/// A generated toolpath segment with its transformation applied.
public struct GeneratedPath: Codable, Sendable {

    public var transform: Transform
    public var segments: [PathSegment]

    public init(transform: Transform, segments: [PathSegment] = []) {
        self.transform = transform
        self.segments = segments
    }
}

// MARK: - Transform

/// A transformation applied to a path during array copy generation.
public struct Transform: Codable, Sendable, Equatable {

    public let translationX: Double
    public let translationY: Double
    public let rotationDegrees: Double
    public let scaleX: Double
    public let scaleY: Double

    public init(
        translationX: Double = 0.0,
        translationY: Double = 0.0,
        rotationDegrees: Double = 0.0,
        scaleX: Double = 1.0,
        scaleY: Double = 1.0
    ) {
        self.translationX = translationX
        self.translationY = translationY
        self.rotationDegrees = rotationDegrees
        self.scaleX = scaleX
        self.scaleY = scaleY
    }

    /// Identity transform.
    public static let identity = Transform()
}

// MARK: - Path Segment

/// A single segment within a generated toolpath.
public struct PathSegment: Codable, Sendable {

    public enum SegmentType: String, Codable, Sendable {
        case line
        case arcCW
        case arcCCW
        case rapid

        public var displayName: String {
            switch self {
            case .line: return "Line"
            case .arcCW: return "Arc CW"
            case .arcCCW: return "Arc CCW"
            case .rapid: return "Rapid"
            }
        }
    }

    public let type: SegmentType
    public let x: Double
    public let y: Double
    public let z: Double
    public let radius: Double?  // arc radius, nil for lines

    public init(type: SegmentType, x: Double, y: Double, z: Double, radius: Double? = nil) {
        self.type = type
        self.x = x
        self.y = y
        self.z = z
        self.radius = radius
    }
}

// MARK: - Preview (Xcode only)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct ArrayCopyToolpath_Previews: PreviewProvider {
    static var previews: some View {
        Text("Array copy toolpath is a non-visual component")
    }
}
#endif

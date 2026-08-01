import Foundation

// MARK: - Zero Plane Type

/// How a zero plane is determined for a job.
public enum ZeroPlaneType: String, Codable, Sendable {
    /// Zero plane is manually set by the user.
    case manual
    /// Zero plane is derived from a surface scan or measurement.
    case surface
    /// Zero plane references another component's geometry.
    case component
}

// MARK: - Zero Plane

/// Represents the zero plane setting for a job.
/// The zero plane defines the origin (X, Y, Z) for toolpath coordinates.
public struct ZeroPlane: Identifiable, Codable, Sendable {
    /// Unique identifier.
    public let id: UUID

    /// Display name (e.g., "Top Surface", "Bottom Surface", "Custom").
    public var name: String

    /// The type of zero plane.
    public var type: ZeroPlaneType

    /// X origin in mm.
    public var x: Double

    /// Y origin in mm.
    public var y: Double

    /// Z origin in mm.
    public var z: Double

    /// Component to reference for automatic zero plane calculation (nil = manual).
    public var referenceComponent: UUID?

    /// Z offset applied from the reference (mm).
    public var offsetZ: Double

    public init(
        id: UUID = UUID(),
        name: String,
        type: ZeroPlaneType,
        x: Double,
        y: Double,
        z: Double,
        referenceComponent: UUID? = nil,
        offsetZ: Double = 0.0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.x = x
        self.y = y
        self.z = z
        self.referenceComponent = referenceComponent
        self.offsetZ = offsetZ
    }

    /// Effective Z value after applying the offset.
    public var effectiveZ: Double {
        z + offsetZ
    }
}

// MARK: - Zero Plane Manager

/// Manages zero planes for a job. ObservableObject for SwiftUI integration.
@MainActor
public final class ZeroPlaneManager: ObservableObject {
    @Published public var planes: [ZeroPlane] = []
    @Published public var activePlaneID: UUID?

    /// Number of planes.
    public var count: Int { planes.count }

    /// Add a new zero plane and return its ID.
    public func addPlane(_ name: String, type: ZeroPlaneType) -> UUID {
        let plane = ZeroPlane(name: name, type: type, x: 0.0, y: 0.0, z: 0.0)
        planes.append(plane)
        // Auto-activate if this is the first plane
        if activePlaneID == nil {
            activePlaneID = plane.id
        }
        return plane.id
    }

    /// Remove a zero plane by ID. Returns true if removed.
    public func removePlane(_ id: UUID) -> Bool {
        guard let idx = planes.firstIndex(where: { $0.id == id }) else { return false }
        planes.remove(at: idx)
        if activePlaneID == id {
            activePlaneID = planes.first?.id
        }
        return true
    }

    /// Set the active zero plane by ID. Returns true if successful.
    public func setActive(_ id: UUID) -> Bool {
        guard planes.contains(where: { $0.id == id }) else { return false }
        activePlaneID = id
        return true
    }

    /// Get the currently active zero plane.
    public func getActivePlane() -> ZeroPlane? {
        guard let id = activePlaneID else { return nil }
        return planes.first(where: { $0.id == id })
    }

    /// Update a zero plane's values. Only updates non-nil parameters.
    public func updatePlane(_ id: UUID, x: Double? = nil, y: Double? = nil, z: Double? = nil, offsetZ: Double? = nil) -> Bool {
        guard let idx = planes.firstIndex(where: { $0.id == id }) else { return false }
        if let x = x { planes[idx].x = x }
        if let y = y { planes[idx].y = y }
        if let z = z { planes[idx].z = z }
        if let offsetZ = offsetZ { planes[idx].offsetZ = offsetZ }
        return true
    }

    /// Convenience: get the active plane's origin coordinates.
    public var activeOrigin: (x: Double, y: Double, z: Double)? {
        getActivePlane().map { ($0.x, $0.y, $0.effectiveZ) }
    }
}

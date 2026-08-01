import Foundation

// MARK: - Interactive Shape Handles

/// Represents a 3D handle for interactive component manipulation.
public struct ShapeHandle: Identifiable, Codable, Sendable {
    public let id: UUID
    
    /// The component this handle belongs to
    public var componentID: UUID
    
    /// Handle type
    public var handleType: HandleType
    
    /// Handle position in 3D space (mm)
    public var position: HandlePosition
    
    /// Handle size in points
    public var size: Double
    
    /// Handle is being dragged
    public var isDragging: Bool
    
    /// Handle is selected
    public var isSelected: Bool
    
    public init(
        id: UUID = UUID(),
        componentID: UUID,
        handleType: HandleType = .translate,
        position: HandlePosition = HandlePosition(),
        size: Double = 12.0,
        isDragging: Bool = false,
        isSelected: Bool = false
    ) {
        self.id = id
        self.componentID = componentID
        self.handleType = handleType
        self.position = position
        self.size = max(6.0, min(48.0, size))
        self.isDragging = isDragging
        self.isSelected = isSelected
    }
}

/// The type of 3D manipulation handle
public enum HandleType: String, Codable, Sendable {
    case translate
    case rotate
    case scale
    case scaleNonUniform
    case tilt
    case custom
}

/// 3D position for a handle
public struct HandlePosition: Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    
    public init(x: Double = 0.0, y: Double = 0.0, z: Double = 0.0) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    /// Distance from origin
    public var distance: Double {
        sqrt(x * x + y * y + z * z)
    }
    
    /// Normalized direction vector
    public var direction: (Double, Double, Double) {
        let d = distance
        guard d > 0 else { return (0, 0, 0) }
        return (x / d, y / d, z / d)
    }
}

/// Axis for handle manipulation
public enum HandleAxis: String, Codable, Sendable {
    case x
    case y
    case z
    case xy
    case xz
    case yz
    case all
}

/// Handle color scheme
public struct HandleColors: Sendable {
    public static let xColor = "FF0000"
    public static let yColor = "00FF00"
    public static let zColor = "0000FF"
    public static let xyColor = "FFFF00"
    public static let xzColor = "FF00FF"
    public static let yzColor = "00FFFF"
    public static let allColor = "FFFFFF"
    public static let selectedColor = "FFAA00"
    public static let draggingColor = "FF6600"
}

// MARK: - ShapeHandleManager

/// Manages interactive shape handles for 3D components.
public final class ShapeHandleManager: ObservableObject {
    @Published public var handles: [ShapeHandle]
    @Published public var activeHandleID: UUID?
    @Published public var selectedAxis: HandleAxis?
    
    public init() {
        self.handles = []
        self.activeHandleID = nil
        self.selectedAxis = nil
    }
    
    /// Creates handles for a component (one per axis + center).
    @discardableResult
    public func createHandles(for componentID: UUID) -> [UUID] {
        let axisTypes: [(HandleType, HandlePosition)] = [
            (.translate, HandlePosition(x: 1.0, y: 0.0, z: 0.0)),
            (.translate, HandlePosition(x: 0.0, y: 1.0, z: 0.0)),
            (.translate, HandlePosition(x: 0.0, y: 0.0, z: 1.0)),
            (.rotate, HandlePosition(x: 1.0, y: 0.0, z: 0.0)),
            (.rotate, HandlePosition(x: 0.0, y: 1.0, z: 0.0)),
            (.rotate, HandlePosition(x: 0.0, y: 0.0, z: 1.0)),
            (.scale, HandlePosition(x: 0.0, y: 0.0, z: 0.0)),
        ]
        
        var ids: [UUID] = []
        for (type, pos) in axisTypes {
            let id = UUID()
            let handle = ShapeHandle(
                id: id,
                componentID: componentID,
                handleType: type,
                position: pos
            )
            handles.append(handle)
            ids.append(id)
        }
        return ids
    }
    
    /// Removes all handles for a component.
    public func removeHandles(for componentID: UUID) {
        handles.removeAll { $0.componentID == componentID }
        if let activeID = activeHandleID, !handles.contains(where: { $0.id == activeID }) {
            activeHandleID = nil
        }
    }
    
    /// Selects a handle by ID.
    public func selectHandle(_ id: UUID) {
        guard let idx = handles.firstIndex(where: { $0.id == id }) else { return }
        // Deselect all others
        for i in handles.indices {
            handles[i].isSelected = false
        }
        handles[idx].isSelected = true
        activeHandleID = id
        
        // Determine axis from position
        let pos = handles[idx].position
        if pos.x != 0 && pos.y == 0 && pos.z == 0 {
            selectedAxis = .x
        } else if pos.x == 0 && pos.y != 0 && pos.z == 0 {
            selectedAxis = .y
        } else if pos.x == 0 && pos.y == 0 && pos.z != 0 {
            selectedAxis = .z
        } else if pos.x != 0 && pos.y != 0 && pos.z == 0 {
            selectedAxis = .xy
        } else if pos.x != 0 && pos.y == 0 && pos.z != 0 {
            selectedAxis = .xz
        } else if pos.x == 0 && pos.y != 0 && pos.z != 0 {
            selectedAxis = .yz
        } else {
            selectedAxis = .all
        }
    }
    
    /// Gets handles for a component.
    public func getHandles(for componentID: UUID) -> [ShapeHandle] {
        handles.filter { $0.componentID == componentID }
    }
    
    /// Gets the active handle.
    public func getActiveHandle() -> ShapeHandle? {
        guard let id = activeHandleID else { return nil }
        return handles.first(where: { $0.id == id })
    }
    
    /// Starts dragging a handle.
    public func startDrag(_ id: UUID) {
        guard let idx = handles.firstIndex(where: { $0.id == id }) else { return }
        handles[idx].isDragging = true
    }
    
    /// Ends dragging a handle.
    public func endDrag(_ id: UUID) {
        guard let idx = handles.firstIndex(where: { $0.id == id }) else { return }
        handles[idx].isDragging = false
    }
    
    /// Updates handle position during drag.
    public func updateHandlePosition(_ id: UUID, x: Double, y: Double, z: Double) {
        guard let idx = handles.firstIndex(where: { $0.id == id }) else { return }
        handles[idx].position = HandlePosition(x: x, y: y, z: z)
    }
    
    /// Clears all handles.
    public func clearAll() {
        handles.removeAll()
        activeHandleID = nil
        selectedAxis = nil
    }
}

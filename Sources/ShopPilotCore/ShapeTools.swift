import Foundation

// MARK: - Shape Tools

/// Represents a shape transformation applied to a 3D component.
public struct ShapeTool: Identifiable, Codable, Sendable {
    public let id: UUID
    
    /// The component this shape tool applies to
    public var componentID: UUID
    
    /// Shape type
    public var shapeType: ShapeType
    
    /// Parameters specific to the shape type
    public var parameters: ShapeParameters
    
    /// Active
    public var active: Bool
    
    public init(
        id: UUID = UUID(),
        componentID: UUID,
        shapeType: ShapeType = .angled,
        parameters: ShapeParameters = ShapeParameters(),
        active: Bool = true
    ) {
        self.id = id
        self.componentID = componentID
        self.shapeType = shapeType
        self.parameters = parameters
        self.active = active
    }
}

/// The type of shape transformation
public enum ShapeType: String, Codable, Sendable {
    case angled
    case round
    case smooth
    case flat
    case custom

    public var displayName: String {
        switch self {
        case .angled: return "Angled"
        case .round: return "Round"
        case .smooth: return "Smooth"
        case .flat: return "Flat"
        case .custom: return "Custom"
        }
    }
}

/// Parameters for shape transformations
public struct ShapeParameters: Codable, Sendable {
    /// Angle in degrees (for angled)
    public var angle: Double
    
    /// Radius in mm (for round)
    public var radius: Double
    
    /// Smoothness factor 0.0-1.0 (for smooth)
    public var smoothness: Double
    
    /// Height of flat plane (for flat)
    public var flatHeight: Double
    
    /// Custom shape function (for custom)
    public var customFunction: String?
    
    public init(
        angle: Double = 45.0,
        radius: Double = 2.0,
        smoothness: Double = 0.5,
        flatHeight: Double = 0.0,
        customFunction: String? = nil
    ) {
        self.angle = angle
        self.radius = max(0.0, radius)
        self.smoothness = max(0.0, min(1.0, smoothness))
        self.flatHeight = flatHeight
        self.customFunction = customFunction
    }
}

// MARK: - ShapeToolManager

/// Manages shape tools for 3D components.
public final class ShapeToolManager: ObservableObject {
    @Published public var shapeTools: [ShapeTool]
    @Published public var activeToolID: UUID?
    
    public init() {
        self.shapeTools = []
        self.activeToolID = nil
    }
    
    /// Adds a new shape tool to a component.
    @discardableResult
    public func addShapeTool(
        for componentID: UUID,
        shapeType: ShapeType = .angled,
        angle: Double = 45.0,
        radius: Double = 2.0,
        smoothness: Double = 0.5,
        flatHeight: Double = 0.0
    ) -> UUID {
        let id = UUID()
        let tool = ShapeTool(
            id: id,
            componentID: componentID,
            shapeType: shapeType,
            parameters: ShapeParameters(
                angle: angle,
                radius: radius,
                smoothness: smoothness,
                flatHeight: flatHeight
            )
        )
        shapeTools.append(tool)
        return id
    }
    
    /// Removes a shape tool by ID.
    public func removeShapeTool(_ id: UUID) {
        guard let idx = shapeTools.firstIndex(where: { $0.id == id }) else { return }
        shapeTools.remove(at: idx)
        if activeToolID == id {
            activeToolID = nil
        }
    }
    
    /// Sets the active shape tool.
    public func setActive(_ id: UUID) {
        guard shapeTools.contains(where: { $0.id == id }) else { return }
        activeToolID = id
    }
    
    /// Gets the active shape tool.
    public func getActiveTool() -> ShapeTool? {
        guard let id = activeToolID else { return nil }
        return shapeTools.first(where: { $0.id == id })
    }
    
    /// Updates shape tool parameters.
    public func updateParameters(
        _ id: UUID,
        angle: Double? = nil,
        radius: Double? = nil,
        smoothness: Double? = nil,
        flatHeight: Double? = nil
    ) {
        guard let idx = shapeTools.firstIndex(where: { $0.id == id }) else { return }
        if let angle = angle {
            shapeTools[idx].parameters.angle = angle
        }
        if let radius = radius {
            shapeTools[idx].parameters.radius = max(0.0, radius)
        }
        if let smoothness = smoothness {
            shapeTools[idx].parameters.smoothness = max(0.0, min(1.0, smoothness))
        }
        if let flatHeight = flatHeight {
            shapeTools[idx].parameters.flatHeight = flatHeight
        }
    }
    
    /// Toggles the active state of a shape tool.
    public func toggleActive(_ id: UUID) {
        guard let idx = shapeTools.firstIndex(where: { $0.id == id }) else { return }
        shapeTools[idx].active.toggle()
    }
    
    /// Gets all shape tools for a component.
    public func getShapeTools(for componentID: UUID) -> [ShapeTool] {
        shapeTools.filter { $0.componentID == componentID }
    }
    
    /// Clears all shape tools for a component.
    public func clearShapeTools(for componentID: UUID) {
        shapeTools.removeAll { $0.componentID == componentID }
    }
}

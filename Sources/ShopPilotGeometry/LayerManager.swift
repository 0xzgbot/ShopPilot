import Foundation

// MARK: - Layer Model

/// Represents a single design layer with vector shapes.
public struct DesignLayer: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var shapes: [VectorShape]
    public var isVisible: Bool
    public var isLocked: Bool
    public var opacity: Double // 0.0 to 1.0
    
    public init(id: UUID = UUID(), name: String, shapes: [VectorShape] = [], isVisible: Bool = true, isLocked: Bool = false, opacity: Double = 1.0) {
        self.id = id
        self.name = name
        self.shapes = shapes
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.opacity = max(0.0, min(1.0, opacity))
    }
    
    public static func == (lhs: DesignLayer, rhs: DesignLayer) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Layer Manager

/// Manages the layer stack for a design document.
public final class LayerManager: ObservableObject {
    
    @Published public private(set) var layers: [DesignLayer] = []
    @Published public var activeLayerId: UUID?
    
    // MARK: - CRUD
    
    /// Create a new empty layer and add it to the top of the stack.
    public func createLayer(name: String = "Layer") -> DesignLayer {
        let layer = DesignLayer(name: name)
        layers.append(layer)
        if activeLayerId == nil {
            activeLayerId = layer.id
        }
        return layer
    }
    
    /// Delete a layer by ID. If it's the active layer, activate another.
    @discardableResult
    public func deleteLayer(_ id: UUID) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return false }
        
        if layers.count <= 1 {
            // Cannot delete the last layer — clear it instead
            var layer = layers[index]
            layer.shapes.removeAll()
            layers[index] = layer
            return true
        }
        
        let wasActive = activeLayerId == id
        layers.remove(at: index)
        
        if wasActive, !layers.isEmpty {
            activeLayerId = layers[min(index, layers.count - 1)].id
        }
        
        return true
    }
    
    /// Rename a layer.
    public func renameLayer(_ id: UUID, to name: String) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return false }
        layers[index].name = name.isEmpty ? "Layer" : name
        return true
    }
    
    /// Duplicate a layer with all its shapes.
    public func duplicateLayer(_ id: UUID) -> DesignLayer? {
        guard let source = layers.first(where: { $0.id == id }) else { return nil }
        let copy = DesignLayer(name: source.name + " Copy", shapes: source.shapes, isVisible: true, isLocked: false, opacity: source.opacity)
        layers.append(copy)
        activeLayerId = copy.id
        return copy
    }
    
    // MARK: - Active Layer
    
    /// Get the currently active layer.
    public var activeLayer: DesignLayer? {
        guard let id = activeLayerId else { return nil }
        return layers.first(where: { $0.id == id })
    }
    
    /// Set the active layer by ID.
    public func setActiveLayer(_ id: UUID) -> Bool {
        guard layers.contains(where: { $0.id == id }) else { return false }
        activeLayerId = id
        return true
    }
    
    // MARK: - Shape Operations
    
    /// Add a shape to the active layer.
    public func addShape(_ shape: VectorShape) -> Bool {
        guard let id = activeLayerId, !isLayerLocked(id) else { return false }
        guard var index = layers.firstIndex(where: { $0.id == id }) else { return false }
        var layer = layers[index]
        layer.shapes.append(shape)
        layers[index] = layer
        return true
    }
    
    /// Remove a shape from the active layer by UUID.
    public func removeShape(_ id: UUID) -> Bool {
        guard let layerId = activeLayerId, !isLayerLocked(layerId) else { return false }
        guard var lIndex = layers.firstIndex(where: { $0.id == layerId }) else { return false }
        if let sIndex = layers[lIndex].shapes.firstIndex(where: { shapeId($0) == id }) {
            var layer = layers[lIndex]
            layer.shapes.remove(at: sIndex)
            layers[lIndex] = layer
            return true
        }
        return false
    }
    
    /// Get all visible shapes across all layers (for preview/toolpath).
    public var visibleShapes: [VectorShape] {
        layers.filter(\.isVisible).flatMap(\.shapes)
    }
    
    /// Get all shapes on a specific layer.
    public func shapes(onLayer id: UUID) -> [VectorShape]? {
        layers.first(where: { $0.id == id })?.shapes
    }
    
    // MARK: - Visibility & Lock
    
    /// Toggle visibility of a layer.
    public func toggleVisibility(_ id: UUID) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return false }
        layers[index].isVisible.toggle()
        return true
    }
    
    /// Toggle lock state of a layer.
    public func toggleLock(_ id: UUID) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return false }
        layers[index].isLocked.toggle()
        return true
    }
    
    /// Check if a layer is locked.
    public func isLayerLocked(_ id: UUID) -> Bool {
        layers.first(where: { $0.id == id })?.isLocked ?? false
    }
    
    // MARK: - Reorder
    
    /// Move a layer up in the stack (toward top/foreground).
    public func moveLayerUp(_ id: UUID) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == id }), index < layers.count - 1 else { return false }
        layers.swapAt(index, index + 1)
        return true
    }
    
    /// Move a layer down in the stack (toward bottom/background).
    public func moveLayerDown(_ id: UUID) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == id }), index > 0 else { return false }
        layers.swapAt(index, index - 1)
        return true
    }
    
    // MARK: - Clear
    
    /// Remove all shapes from the active layer.
    public func clearActiveLayer() -> Bool {
        guard let id = activeLayerId, !isLayerLocked(id) else { return false }
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return false }
        var layer = layers[index]
        layer.shapes.removeAll()
        layers[index] = layer
        return true
    }
    
    /// Clear all layers and reset to a single empty layer.
    public func resetAllLayers() {
        layers = [DesignLayer(name: "Layer 1")]
        activeLayerId = layers[0].id
    }
}

// MARK: - Helpers

private func shapeId(_ shape: VectorShape) -> UUID? {
    (shape as? Identifiable)?.id as? UUID
}

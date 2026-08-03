import Foundation

// MARK: - Vector Selection Mode

/// How the user selects vectors for a toolpath strategy.
public enum VectorSelectionMode {
    /// Select individual vectors by tapping/clicking.
    case individual
    /// Select all vectors in the current layer.
    case allInLayer
    /// Select vectors within a rectangular region.
    case rectangularRegion
    /// Select vectors that intersect a selection shape.
    case intersection
    
    public var displayName: String {
        switch self {
        case .individual: return "Individual"
        case .allInLayer: return "All in Layer"
        case .rectangularRegion: return "Rectangular Region"
        case .intersection: return "Intersection"
        }
    }
}

// MARK: - Selected Vector Set

/// A set of vectors selected for a toolpath strategy.
public struct SelectedVectorSet: Identifiable {
    
    public let id = UUID()
    
    /// The selected vectors.
    public var vectors: [VectorPath]
    
    /// The selection mode used.
    public var mode: VectorSelectionMode
    
    /// Whether the set is empty.
    public var isEmpty: Bool { vectors.isEmpty }
    
    /// Total length of all selected vectors.
    public var totalLength: Double {
        vectors.reduce(0.0) { $0 + $1.length }
    }
    
    /// Bounding box of all selected vectors.
    public var boundingBox: (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        guard !vectors.isEmpty else { return nil }
        
        var allPoints: [VectorPoint] = []
        for vector in vectors {
            allPoints.append(contentsOf: vector.points)
        }
        
        guard !allPoints.isEmpty else { return nil }
        
        let xs = allPoints.map(\.x)
        let ys = allPoints.map(\.y)
        
        return (xs.min()!, ys.min()!, xs.max()!, ys.max()!)
    }
    
    /// Add a vector to the selection.
    public mutating func addVector(_ vector: VectorPath) {
        vectors.append(vector)
    }
    
    /// Remove a vector from the selection by ID.
    @discardableResult
    public mutating func removeVector(id: UUID) -> Bool {
        if let index = vectors.firstIndex(where: { $0.id == id }) {
            vectors.remove(at: index)
            return true
        }
        return false
    }
    
    /// Clear all selected vectors.
    public mutating func clear() {
        vectors.removeAll()
    }
}

// MARK: - Toolpath Strategy

/// A toolpath strategy that can be applied to selected vectors.
public protocol ToolpathStrategy {
    
    /// Display name of the strategy.
    var displayName: String { get }
    
    /// Description of what this strategy does.
    var description: String { get }
    
    /// Icon name for UI representation.
    var iconName: String { get }
    
    /// Whether this strategy requires selected vectors.
    var requiresSelection: Bool { get }
    
    /// Apply the strategy to the given vectors and parameters.
    func apply(vectors: [VectorPath], params: Any) -> String?
}

// MARK: - Strategy Registry

/// Registry of available toolpath strategies.
public final class StrategyRegistry {
    
    private var strategies: [String: ToolpathStrategy] = [:]
    
    /// Register a strategy.
    public func register(_ strategy: ToolpathStrategy, id: String) {
        strategies[id] = strategy
    }
    
    /// Get a strategy by ID.
    public func strategy(forId id: String) -> ToolpathStrategy? {
        strategies[id]
    }
    
    /// Get all registered strategies.
    public var allStrategies: [ToolpathStrategy] {
        Array(strategies.values)
    }
    
    /// Check if a strategy is registered.
    public func hasStrategy(forId id: String) -> Bool {
        strategies[id] != nil
    }
}

// MARK: - Vector Selector

/// Manages vector selection for toolpath strategies.
public final class VectorSelector: ObservableObject {
    
    @Published public var selectedSet: SelectedVectorSet = SelectedVectorSet(vectors: [], mode: .individual)
    @Published public var availableVectors: [VectorPath] = []
    @Published public var currentMode: VectorSelectionMode = .individual
    
    /// Add a vector to the available pool.
    public func addAvailableVector(_ vector: VectorPath) {
        availableVectors.append(vector)
    }
    
    /// Remove a vector from the available pool.
    @discardableResult
    public func removeAvailableVector(id: UUID) -> Bool {
        if let index = availableVectors.firstIndex(where: { $0.id == id }) {
            availableVectors.remove(at: index)
            return true
        }
        return false
    }
    
    /// Select a vector by ID.
    public func selectVector(id: UUID) -> Bool {
        if let vector = availableVectors.first(where: { $0.id == id }) {
            selectedSet.addVector(vector)
            return true
        }
        return false
    }
    
    /// Deselect a vector by ID.
    public func deselectVector(id: UUID) -> Bool {
        if let index = selectedSet.vectors.firstIndex(where: { $0.id == id }) {
            selectedSet.vectors.remove(at: index)
            return true
        }
        return false
    }
    
    /// Select all available vectors.
    public func selectAll() {
        selectedSet.vectors = availableVectors
        selectedSet.mode = .allInLayer
    }
    
    /// Clear the selection.
    public func clearSelection() {
        selectedSet.clear()
    }
    
    /// Get vectors that intersect a rectangular region.
    public func selectInRegion(minX: Double, minY: Double, maxX: Double, maxY: Double) -> [VectorPath] {
        availableVectors.filter { vector in
            if let bounds = vector.bounds {
                return !(bounds.maxX < minX || bounds.minX > maxX || bounds.maxY < minY || bounds.minY > maxY)
            }
            return false
        }
    }
    
    /// Get the number of selected vectors.
    public var selectionCount: Int { selectedSet.vectors.count }
    
    /// Check if any vectors are selected.
    public var hasSelection: Bool { !selectedSet.isEmpty }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct VectorSelector_Previews: PreviewProvider {
    static var previews: some View {
        Text("Vector selector is a non-visual component")
    }
}
#endif

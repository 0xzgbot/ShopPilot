import Foundation

// MARK: - Vector (2D path on a layer)

/// A 2D point in mm coordinates. Codable-compatible struct.
public struct VectorPoint: Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }
}

public struct VectorPath: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var points: [VectorPoint]  // 2D coordinates in mm
    public var isClosed: Bool
    public var layerId: UUID

    /// Bounding box of this vector path.
    public var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return (xs.min()!, ys.min()!, xs.max()!, ys.max()!)
    }

    /// Length of this vector path (approximate for polylines).
    public var length: Double {
        guard points.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<points.count {
            let dx = points[i].x - points[i-1].x
            let dy = points[i].y - points[i-1].y
            total += sqrt(dx*dx + dy*dy)
        }
        return total
    }

    public init(
        id: UUID = UUID(),
        name: String = "Path",
        points: [VectorPoint] = [],
        isClosed: Bool = false,
        layerId: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.points = points
        self.isClosed = isClosed
        self.layerId = layerId
    }
}

// MARK: - Layer

/// A single layer within a Sheet. Contains vectors and optionally toolpaths.
public struct Layer: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var isVisible: Bool
    public var isLocked: Bool
    public var vectors: [VectorPath]

    /// Toolpath IDs associated with this layer (references, not stored here).
    public var toolpathIds: [UUID]

    public init(
        id: UUID = UUID(),
        name: String = "Layer 1",
        isVisible: Bool = true,
        isLocked: Bool = false,
        vectors: [VectorPath] = [],
        toolpathIds: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.vectors = vectors
        self.toolpathIds = toolpathIds
    }

    /// Add a vector to this layer.
    public mutating func addVector(_ vector: VectorPath) {
        vectors.append(vector)
    }

    /// Remove a vector by ID.
    @discardableResult
    public mutating func removeVector(id: UUID) -> Bool {
        guard let index = vectors.firstIndex(where: { $0.id == id }) else { return false }
        vectors.remove(at: index)
        return true
    }

    /// Total length of all vectors in this layer.
    public var totalVectorLength: Double {
        vectors.reduce(0) { $0 + $1.length }
    }

    /// Number of visible vectors.
    public var visibleVectorCount: Int {
        isVisible ? vectors.count : 0
    }
}

// MARK: - DirtyDocument Protocol

/// Protocol for types that track document changes and support undo/redo.
public protocol DirtyDocument: AnyObject {
    /// Whether the document has unsaved changes.
    var isDirty: Bool { get }

    /// Mark this document as changed (dirty).
    func markDirty()

    /// Undo the last change. Returns true if an undo was performed.
    @discardableResult
    func undo() -> Bool

    /// Redo the last undone change. Returns true if a redo was performed.
    @discardableResult
    func redo() -> Bool

    /// Clear the undo/redo stack (e.g., after save).
    func clearUndoStack()
}

// MARK: - UndoManagerDocument (default implementation)

/// Base class providing UndoManager-based dirty tracking for document types.
open class UndoManagerDocument: DirtyDocument {
    public let undoManager = UndoManager()

    public var isDirty: Bool {
        undoManager.canUndo || undoManager.canRedo
    }

    open func markDirty() {
        // UndoManager tracks changes automatically when actions are wrapped in beginEditing/endEditing.
        // This method can be called explicitly for programmatic state changes.
    }

    @discardableResult
    open func undo() -> Bool {
        guard undoManager.canUndo else { return false }
        undoManager.undo()
        return true
    }

    @discardableResult
    open func redo() -> Bool {
        guard undoManager.canRedo else { return false }
        undoManager.redo()
        return true
    }

    open func clearUndoStack() {
        undoManager.removeAllActions()
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct Layer_Previews: PreviewProvider {
    static var previews: some View {
        Text("Layer preview requires Xcode Previews")
    }
}
#endif

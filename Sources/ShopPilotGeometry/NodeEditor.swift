import Foundation

// MARK: - Node Handle

/// An editable control point on a vector shape.
public struct NodeHandle: Codable, Equatable, Hashable {
    public let id: UUID
    public var point: VectorPoint
    
    public init(id: UUID = UUID(), point: VectorPoint) {
        self.id = id
        self.point = point
    }
}

// MARK: - Shape Node Editor

/// Manages editable nodes for vector shapes.
public final class ShapeNodeEditor: ObservableObject {
    
    @Published public var nodes: [NodeHandle] = []

    public init() {}
    
    /// Add a node at the given point.
    public func addNode(at point: VectorPoint) {
        let handle = NodeHandle(point: point)
        undoStack.append(.add(id: handle.id, point: point))
        nodes.append(handle)
    }
    
    /// Remove a node by ID.
    public func removeNode(id: UUID) {
        nodes.removeAll { $0.id == id }
    }
    
    /// Move a node to a new position.
    public func moveNode(id: UUID, to point: VectorPoint) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        // No-op move: nothing changed, no undo snapshot (SPK-0201b).
        guard nodes[index].point != point else { return }
        let before = nodes[index].point
        undoStack.append(.move(id: id, from: before))
        nodes[index].point = point
    }

    // MARK: - Undo-last-move (SPK-0201b)

    /// LIFO snapshot of the state BEFORE a mutating operation, so
    /// `undoLastMove` can restore it. `addNode` pushes a "node did not exist"
    /// snapshot; `moveNode` pushes the prior point.
    private enum UndoSnapshot {
        case add(id: UUID, point: VectorPoint)
        case move(id: UUID, from: VectorPoint)
    }

    private var undoStack: [UndoSnapshot] = []

    /// Whether an undo snapshot is available.
    public var canUndoLastMove: Bool {
        !undoStack.isEmpty
    }

    /// Pop the most recent mutation and restore the prior state.
    /// Returns false when the stack is drained.
    @discardableResult
    public func undoLastMove() -> Bool {
        guard let snapshot = undoStack.popLast() else { return false }
        switch snapshot {
        case .add(let id, _):
            nodes.removeAll { $0.id == id }
        case .move(let id, let from):
            if let index = nodes.firstIndex(where: { $0.id == id }) {
                nodes[index].point = from
            }
        }
        return true
    }

    /// Drop the undo history (start a clean edit session).
    public func clearUndoHistory() {
        undoStack.removeAll()
    }
    
    /// Get a node by ID.
    public func getNode(id: UUID) -> NodeHandle? {
        return nodes.first(where: { $0.id == id })
    }
    
    /// Clear all nodes.
    public func clear() {
        nodes.removeAll()
    }
}

// MARK: - VectorShape Extensions for Node Editing

extension VectorShape {
    
    /// Extract editable control points from any shape type.
    public func extractNodes() -> [NodeHandle] {
        switch self {
        case .line(let start, let end):
            return [
                NodeHandle(point: start),
                NodeHandle(point: end)
            ]
        case .circle(let center, let radius):
            // Circle: center handle + rim handle (drag rim to resize).
            return [
                NodeHandle(id: UUID(), point: center),
                NodeHandle(id: UUID(), point: VectorPoint(x: center.x + radius, y: center.y))
            ]
        case .rectangle(let origin, let width, let height):
            // Rectangle: 4 corner handles (order: origin, maxX, maxX+maxY, maxY).
            let p0 = origin
            let p1 = VectorPoint(x: origin.x + width, y: origin.y)
            let p2 = VectorPoint(x: origin.x + width, y: origin.y + height)
            let p3 = VectorPoint(x: origin.x, y: origin.y + height)
            return [p0, p1, p2, p3].map { NodeHandle(point: $0) }
        case .arc(let center, _, _, _):
            // Arc represented by center point
            return [NodeHandle(point: center)]
        case .ellipse(let center, _, _, _):
            return [NodeHandle(point: center)]
        case .polygon(let center, _, _, _):
            return [NodeHandle(point: center)]
        case .star(let center, _, _, _, _):
            return [NodeHandle(point: center)]
        case .freehand(let points):
            return points.map { NodeHandle(point: $0) }
        }
    }
    
    /// Reconstruct a modified shape from edited node positions.
    public func updateFromNodes(_ nodes: [NodeHandle]) -> VectorShape {
        guard !nodes.isEmpty else { return self }
        
        switch self {
        case .line(let start, let end):
            if nodes.count >= 2 {
                return .line(start: nodes[0].point, end: nodes[1].point)
            } else if nodes.count == 1 {
                let midX = (start.x + end.x) / 2.0
                let midY = (start.y + end.y) / 2.0
                let dx = nodes[0].point.x - midX
                let dy = nodes[0].point.y - midY
                return .line(start: VectorPoint(x: start.x + dx, y: start.y + dy),
                           end: VectorPoint(x: end.x + dx, y: end.y + dy))
            }
            return self
            
        case .circle(let center, let radius):
            if nodes.count >= 2 {
                let newCenter = nodes[0].point
                let newRadius = hypot(nodes[1].point.x - newCenter.x,
                                    nodes[1].point.y - newCenter.y)
                return .circle(center: newCenter, radius: max(newRadius, 0.001))
            } else if nodes.count == 1 {
                return .circle(center: nodes[0].point, radius: radius)
            }
            return self
            
        case .rectangle(let origin, let width, let height):
            if nodes.count >= 4 {
                // 4-corner editing: node 0 is the origin corner, node 2 the
                // opposite corner. Drag either to reshape; the other two follow.
                let newOrigin = nodes[0].point
                let opposite = nodes[2].point
                let newWidth = opposite.x - newOrigin.x
                let newHeight = opposite.y - newOrigin.y
                guard abs(newWidth) > 1e-9, abs(newHeight) > 1e-9 else { return self }
                // Keep the origin corner fixed and allow signed extents.
                return .rectangle(
                    origin: newOrigin,
                    width: newWidth,
                    height: newHeight
                )
            } else if nodes.count >= 1 {
                let dx = nodes[0].point.x - origin.x
                let dy = nodes[0].point.y - origin.y
                return .rectangle(origin: VectorPoint(x: origin.x + dx, y: origin.y + dy),
                                width: width, height: height)
            }
            return self
            
        case .arc(let center, let radius, let startAngle, let endAngle):
            if nodes.count >= 1 {
                return .arc(center: nodes[0].point, radius: radius,
                          startAngle: startAngle, endAngle: endAngle)
            }
            return self
            
        case .ellipse(let center, let radiusX, let radiusY, let rotation):
            if nodes.count >= 1 {
                return .ellipse(center: nodes[0].point, radiusX: radiusX, radiusY: radiusY, rotation: rotation)
            }
            return self
            
        case .polygon(let center, let radius, let sides, let rotation):
            if nodes.count >= 1 {
                return .polygon(center: nodes[0].point, radius: radius, sides: sides, rotation: rotation)
            }
            return self
            
        case .star(let center, let outerRadius, let innerRadius, let points, let rotation):
            if nodes.count >= 1 {
                return .star(center: nodes[0].point, outerRadius: outerRadius, innerRadius: innerRadius, points: points, rotation: rotation)
            }
            return self
            
        case .freehand(let points):
            if nodes.count >= 1 {
                return .freehand(points: nodes.map { $0.point })
            }
            return self
        }
    }
}


import Foundation

// MARK: - Toolpath Node Type

/// Represents a node in the toolpath tree hierarchy.
public enum ToolpathNodeType {
    /// A single operation (profile, pocket, drill).
    case operation(String)
    /// A group containing child nodes.
    case group(String)
}

// MARK: - Toolpath Tree Node

/// A node in the toolpath tree with dirty state tracking.
public final class ToolpathTreeNode: Identifiable, ObservableObject {
    
    public let id = UUID()
    public let name: String
    public let type: ToolpathNodeType
    
    /// Child nodes in the tree.
    @Published public var children: [ToolpathTreeNode] = []
    
    /// Whether this node's toolpath needs recalculation.
    @Published public var isDirty: Bool = false
    
    /// The computed toolpath result (if any).
    @Published public var toolpathResult: String? = nil
    
    /// Estimated time for this operation in seconds.
    @Published public var estimatedTimeSeconds: Double = 0.0
    
    /// Whether the node is expanded in the UI.
    @Published public var isExpanded: Bool = false

    /// ID of the tool assigned to this operation (nil = none selected yet).
    /// Resolved against the session's `ToolDatabase` for display/params.
    @Published public var toolID: UUID?

    /// Parent node (if any).
    weak var parent: ToolpathTreeNode?

    public init(name: String, type: ToolpathNodeType) {
        self.name = name
        self.type = type
    }

    /// Assign a tool to this operation. Any tool change invalidates the
    /// computed result, so the node (and its ancestors) are marked dirty.
    public func assignTool(_ toolID: UUID?) {
        guard self.toolID != toolID else { return }
        self.toolID = toolID
        if toolID != nil {
            toolpathResult = nil
        }
        markDirty()
    }

    /// Add a child node.
    @discardableResult
    public func addChild(_ child: ToolpathTreeNode) -> ToolpathTreeNode {
        child.parent = self
        children.append(child)
        return child
    }

    /// Remove a child node by ID (direct children only).
    @discardableResult
    public func removeChild(id: UUID) -> Bool {
        if let index = children.firstIndex(where: { $0.id == id }) {
            children.remove(at: index)
            return true
        }
        return false
    }

    /// Recursively find a descendant (or self) by ID.
    public func findNode(id: UUID) -> ToolpathTreeNode? {
        if self.id == id { return self }
        for child in children {
            if let found = child.findNode(id: id) {
                return found
            }
        }
        return nil
    }

    /// Recursively remove a descendant by ID (any depth). Returns true if removed.
    @discardableResult
    public func removeDescendant(id: UUID) -> Bool {
        if let index = children.firstIndex(where: { $0.id == id }) {
            children.remove(at: index)
            return true
        }
        for child in children {
            if child.removeDescendant(id: id) {
                return true
            }
        }
        return false
    }
    
    /// Mark this node and all ancestors as dirty.
    public func markDirty() {
        isDirty = true
        parent?.markDirty()
    }
    
    /// Clear the dirty flag for this node (after recalculation).
    public func clearDirty() {
        isDirty = false
    }
    
    /// Get all dirty nodes in the subtree.
    ///
    /// Only returns dirty *operation* nodes (the nodes that actually hold a
    /// toolpath needing recalculation). Group/root nodes are marked dirty for
    /// UI display, but they contain no toolpath result, so they are excluded
    /// from recalculation and export-blocking semantics.
    public var allDirtyNodes: [ToolpathTreeNode] {
        var result: [ToolpathTreeNode] = []
        
        if isDirty, isOperation {
            result.append(self)
        }
        
        for child in children {
            result.append(contentsOf: child.allDirtyNodes)
        }
        
        return result
    }

    /// True when this node is an operation (not a group/container).
    public var isOperation: Bool {
        if case .operation = type { return true }
        return false
    }
    
    /// Check if any node in the subtree is dirty.
    public var hasDirtyChildren: Bool {
        allDirtyNodes.isEmpty == false
    }
}

// MARK: - Toolpath Tree Manager

/// Manages the toolpath tree with dirty state tracking and batch recalculation.
public final class ToolpathTreeManager: ObservableObject {
    
    @Published public var root: ToolpathTreeNode

    public init(rootName: String = "Toolpaths") {
        self.root = ToolpathTreeNode(name: rootName, type: .group(rootName))
    }

    /// All nodes in the tree (flat list, computed on demand so it never
    /// goes stale when children are added/removed below the root).
    public var allNodes: [ToolpathTreeNode] {
        var result: [ToolpathTreeNode] = []
        func collect(_ node: ToolpathTreeNode) {
            result.append(node)
            for child in node.children {
                collect(child)
            }
        }
        collect(root)
        return result
    }

    /// Add a new operation to the tree.
    public func addOperation(_ name: String) -> ToolpathTreeNode {
        let node = ToolpathTreeNode(name: name, type: .operation(name))
        root.addChild(node)
        return node
    }

    /// Add a new group to the tree.
    public func addGroup(_ name: String) -> ToolpathTreeNode {
        let node = ToolpathTreeNode(name: name, type: .group(name))
        root.addChild(node)
        return node
    }

    /// Remove a node from the tree (any depth). Returns true if removed.
    public func removeNode(id: UUID) -> Bool {
        if id == root.id {
            return false // Can't remove root
        }
        return root.removeDescendant(id: id)
    }

    /// Find a node anywhere in the tree (including the root).
    public func findNode(id: UUID) -> ToolpathTreeNode? {
        root.findNode(id: id)
    }
    
    /// Recalculate all dirty nodes in the tree.
    public func recalculateDirtyNodes() -> [ToolpathTreeNode] {
        let dirtyNodes = root.allDirtyNodes
        
        for node in dirtyNodes {
            // Simulate toolpath recalculation
            node.toolpathResult = "// Toolpath generated for \(node.name)"
            node.isDirty = false
            node.estimatedTimeSeconds = Double.random(in: 10...300)
        }
        
        return dirtyNodes
    }
    
    /// Get count of dirty nodes.
    public var dirtyNodeCount: Int {
        root.allDirtyNodes.count
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct ToolpathTree_Previews: PreviewProvider {
    static var previews: some View {
        Text("Toolpath tree is a non-visual component")
    }
}
#endif

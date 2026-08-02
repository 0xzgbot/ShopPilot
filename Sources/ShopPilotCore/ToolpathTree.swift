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
    
    /// Parent node (if any).
    weak var parent: ToolpathTreeNode?
    
    init(name: String, type: ToolpathNodeType) {
        self.name = name
        self.type = type
    }
    
    /// Add a child node.
    public func addChild(_ child: ToolpathTreeNode) {
        child.parent = self
        children.append(child)
    }
    
    /// Remove a child node by ID.
    @discardableResult
    public func removeChild(id: UUID) -> Bool {
        if let index = children.firstIndex(where: { $0.id == id }) {
            children.remove(at: index)
            return true
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
    public var allDirtyNodes: [ToolpathTreeNode] {
        var result: [ToolpathTreeNode] = []
        
        if isDirty {
            result.append(self)
        }
        
        for child in children {
            result.append(contentsOf: child.allDirtyNodes)
        }
        
        return result
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
    
    /// All nodes in the tree (flat list).
    @Published public var allNodes: [ToolpathTreeNode] = []
    
    public init(rootName: String = "Toolpaths") {
        self.root = ToolpathTreeNode(name: rootName, type: .group(rootName))
        self.allNodes = [root]
    }
    
    /// Add a new operation to the tree.
    public func addOperation(_ name: String) -> ToolpathTreeNode {
        let node = ToolpathTreeNode(name: name, type: .operation(name))
        root.addChild(node)
        updateAllNodes()
        return node
    }
    
    /// Add a new group to the tree.
    public func addGroup(_ name: String) -> ToolpathTreeNode {
        let node = ToolpathTreeNode(name: name, type: .group(name))
        root.addChild(node)
        updateAllNodes()
        return node
    }
    
    /// Remove a node from the tree.
    public func removeNode(id: UUID) -> Bool {
        if id == root.id {
            return false // Can't remove root
        }
        
        let removed = root.removeChild(id: id)
        if removed {
            updateAllNodes()
        }
        return removed
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
    
    /// Update the flat list of all nodes.
    private func updateAllNodes() {
        allNodes = []
        collectNodes(from: root)
    }
    
    private func collectNodes(from node: ToolpathTreeNode) {
        allNodes.append(node)
        
        for child in node.children {
            collectNodes(from: child)
        }
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

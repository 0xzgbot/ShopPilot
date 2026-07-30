import Foundation

// MARK: - Recalculation Strategy

/// How to handle toolpath recalculation when dependencies change.
public enum RecalculationStrategy {
    /// Only recalculate dirty nodes (default).
    case dirtyOnly
    /// Recalculate all nodes regardless of dirty state.
    case allNodes
}

// MARK: - Toolpath Calculator Protocol

/// Protocol for computing toolpaths from vectors and parameters.
public protocol ToolpathCalculator {
    
    /// Compute a toolpath result.
    func calculate() -> String
    
    /// Estimated time in seconds.
    var estimatedTimeSeconds: Double { get }
}

// MARK: - Dirty Node Result

/// Result of recalculating a dirty node.
public struct DirtyNodeResult: Codable, Sendable {
    
    public let nodeId: UUID
    public let nodeName: String
    public let wasDirty: Bool
    public let gcodeOutput: String?
    public let estimatedTimeSeconds: Double
    
    /// Whether the recalculation succeeded.
    public var success: Bool { gcodeOutput != nil }
}

// MARK: - Toolpath Recalculator

/// Handles dirty node tracking and batch recalculation for the toolpath tree.
public final class ToolpathRecalculator: ObservableObject {
    
    private let treeManager: ToolpathTreeManager
    
    @Published public var lastResults: [DirtyNodeResult] = []
    
    init(treeManager: ToolpathTreeManager) {
        self.treeManager = treeManager
    }
    
    /// Recalculate only dirty nodes in the tree.
    public func recalculateDirty() -> [DirtyNodeResult] {
        var results: [DirtyNodeResult] = []
        
        let dirtyNodes = treeManager.root.allDirtyNodes
        
        for node in dirtyNodes {
            // Simulate toolpath calculation
            let gcodeOutput = "// Toolpath generated for \(node.name)\n// G-code would be here"
            
            let result = DirtyNodeResult(
                nodeId: node.id,
                nodeName: node.name,
                wasDirty: true,
                gcodeOutput: gcodeOutput,
                estimatedTimeSeconds: Double.random(in: 10...300)
            )
            
            results.append(result)
            
            // Clear dirty flag and update result
            node.toolpathResult = gcodeOutput
            node.isDirty = false
            node.estimatedTimeSeconds = result.estimatedTimeSeconds
        }
        
        lastResults = results
        return results
    }
    
    /// Recalculate all nodes in the tree regardless of dirty state.
    public func recalculateAll() -> [DirtyNodeResult] {
        var results: [DirtyNodeResult] = []
        
        for node in treeManager.allNodes where node.id != treeManager.root.id {
            // Simulate toolpath calculation
            let gcodeOutput = "// Toolpath generated for \(node.name)\n// G-code would be here"
            
            let result = DirtyNodeResult(
                nodeId: node.id,
                nodeName: node.name,
                wasDirty: node.isDirty,
                gcodeOutput: gcodeOutput,
                estimatedTimeSeconds: Double.random(in: 10...300)
            )
            
            results.append(result)
            
            // Update result
            node.toolpathResult = gcodeOutput
            node.estimatedTimeSeconds = result.estimatedTimeSeconds
        }
        
        lastResults = results
        return results
    }
    
    /// Get total estimated time for all dirty nodes.
    public var totalDirtyTime: Double {
        treeManager.root.allDirtyNodes.reduce(0.0) { $0 + $1.estimatedTimeSeconds }
    }
    
    /// Check if any nodes are dirty.
    public var hasDirtyNodes: Bool {
        !treeManager.root.allDirtyNodes.isEmpty
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct ToolpathRecalculator_Previews: PreviewProvider {
    static var previews: some View {
        Text("Toolpath recalculator is a non-visual component")
    }
}
#endif

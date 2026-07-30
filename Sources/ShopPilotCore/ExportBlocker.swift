import Foundation

// MARK: - Export Validation Result

/// Result of validating a toolpath tree for export.
public struct ExportValidationResult {
    
    public let isValid: Bool
    public let dirtyNodes: [String]
    public let warnings: [String]
    
    /// Whether export is allowed without override.
    public var canExport: Bool { isValid }
    
    /// Whether an expert override is required.
    public var requiresOverride: Bool { !isValid && !dirtyNodes.isEmpty }
}

// MARK: - Export Blocker

/// Manages export blocking when toolpath tree has dirty nodes.
public final class ExportBlocker: ObservableObject {
    
    private let treeManager: ToolpathTreeManager
    
    @Published public var isExportBlocked: Bool = false
    @Published public var blockedReason: String = ""
    @Published public var dirtyNodeNames: [String] = []
    
    init(treeManager: ToolpathTreeManager) {
        self.treeManager = treeManager
    }
    
    /// Validate the toolpath tree for export.
    public func validateForExport() -> ExportValidationResult {
        let dirtyNodes = treeManager.root.allDirtyNodes
        
        if dirtyNodes.isEmpty {
            isExportBlocked = false
            blockedReason = ""
            dirtyNodeNames = []
            return ExportValidationResult(
                isValid: true,
                dirtyNodes: [],
                warnings: []
            )
        }
        
        // Block export - dirty nodes found
        let names = dirtyNodes.map { $0.name }
        isExportBlocked = true
        blockedReason = "\(dirtyNodes.count) toolpath node(s) need recalculation before export"
        dirtyNodeNames = names
        
        return ExportValidationResult(
            isValid: false,
            dirtyNodes: names,
            warnings: ["Export blocked: \(names.joined(separator: ", "))"]
        )
    }
    
    /// Override the export block (expert mode).
    public func overrideExportBlock() -> Bool {
        guard isExportBlocked else { return true }
        
        // Allow export despite dirty nodes
        isExportBlocked = false
        blockedReason = "Export overridden by user"
        
        return true
    }
    
    /// Clear all dirty flags without recalculating.
    public func clearDirtyFlags() {
        for node in treeManager.root.allDirtyNodes {
            node.clearDirty()
        }
        
        isExportBlocked = false
        blockedReason = ""
        dirtyNodeNames = []
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct ExportBlocker_Previews: PreviewProvider {
    static var previews: some View {
        Text("Export blocker is a non-visual component")
    }
}
#endif

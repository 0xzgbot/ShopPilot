import Foundation

// MARK: - Dirty Region Type

/// Types of dirty regions that may need resimulation.
public enum DirtyRegionType {
    /// A single vector was modified.
    case vectorModified(UUID)
    /// Multiple vectors were added/removed.
    case batchChange([UUID])
    /// The entire toolpath tree changed.
    case fullTree
    /// A keep-out zone was modified.
    case keepOutZoneChanged
    
    public var affectedCount: Int {
        switch self {
        case .vectorModified: return 1
        case .batchChange(let ids): return ids.count
        case .fullTree: return Int.max
        case .keepOutZoneChanged: return -1 // All
        }
    }
}

// MARK: - Dirty Region Manager

/// Manages dirty region tracking and selective resimulation.
public final class DirtyRegionManager: ObservableObject {
    
    @Published public var dirtyRegions: [DirtyRegionType] = []
    @Published public var needsResimulation: Bool = false
    
    /// The toolpath simulator for resimulation.
    private let simulator: ToolpathSimulator?
    
    /// The preview manager for updating previews.
    private let previewManager: PreviewManager?
    
    init(simulator: ToolpathSimulator?, previewManager: PreviewManager?) {
        self.simulator = simulator
        self.previewManager = previewManager
    }

    /// Public convenience init (SPK-0316): a manager with no simulator or
    /// preview attached is still a valid dirty-region tracker — callers that
    /// resimulate wire their own simulator/preview in later.
    public init() {
        self.simulator = nil
        self.previewManager = nil
    }
    
    /// Mark a vector as modified and add to dirty regions.
    public func markVectorModified(_ vectorId: UUID) {
        dirtyRegions.append(.vectorModified(vectorId))
        needsResimulation = true
    }
    
    /// Mark multiple vectors as changed.
    public func markBatchChange(_ ids: [UUID]) {
        if !ids.isEmpty {
            dirtyRegions.append(.batchChange(ids))
            needsResimulation = true
        }
    }
    
    /// Mark the entire tree as dirty.
    public func markFullTreeDirty() {
        dirtyRegions.append(.fullTree)
        needsResimulation = true
    }
    
    /// Mark keep-out zones as changed.
    public func markKeepOutZoneChanged() {
        dirtyRegions.append(.keepOutZoneChanged)
        needsResimulation = true
    }
    
    /// Clear all dirty regions and trigger resimulation if needed.
    @discardableResult
    public func clearDirtyRegions() -> Bool {
        guard !dirtyRegions.isEmpty else { return false }
        
        let hadDirtyRegions = needsResimulation
        dirtyRegions.removeAll()
        needsResimulation = false
        
        return hadDirtyRegions
    }
    
    /// Get the total number of affected vectors.
    public var affectedVectorCount: Int {
        dirtyRegions.reduce(0) { $0 + $1.affectedCount }
    }
    
    /// Check if a specific vector is in any dirty region.
    public func isVectorAffected(_ vectorId: UUID) -> Bool {
        for region in dirtyRegions {
            switch region {
            case .vectorModified(let id):
                if id == vectorId { return true }
            case .batchChange(let ids):
                if ids.contains(vectorId) { return true }
            case .fullTree:
                return true
            case .keepOutZoneChanged:
                return true // All vectors affected
            }
        }
        return false
    }
    
    /// Perform selective resimulation for dirty regions (SPK-0315).
    ///
    /// When the dirty set is a PROPER subset of the tree, only the affected
    /// nodes' G-code is re-simulated (`partialLines`) — the caller (Preview)
    /// renders just the delta carving; a full-tree change falls back to the
    /// complete line set. Returns the simulated height samples.
    public func performResimulation(
        partialLines: [String],
        fullLines: [String],
        sheetWidthMm: Double,
        sheetDepthMm: Double,
        stockTopMm: Double,
        cellSizeMm: Double,
        toolRadiusMm: Double? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) async -> ([(x: Double, y: Double, z: Double)], isPartial: Bool) {
        guard needsResimulation else {
            return ([], isPartial: false)
        }

        let isFullTree = dirtyRegions.contains { region in
            if case .fullTree = region { return true }
            if case .keepOutZoneChanged = region { return true }
            return false
        }

        let lines: [String]
        let partial: Bool
        if isFullTree || partialLines.isEmpty {
            lines = fullLines
            partial = false
        } else {
            lines = partialLines
            partial = true
        }
        guard !lines.isEmpty else {
            clearDirtyRegions()
            return ([], isPartial: partial)
        }

        let outcome = await ToolpathSimulator.materialSimulation(
            from: lines,
            sheetWidthMm: sheetWidthMm,
            sheetDepthMm: sheetDepthMm,
            stockTopMm: stockTopMm,
            cellSizeMm: cellSizeMm,
            toolRadiusMm: toolRadiusMm,
            shouldCancel: shouldCancel ?? { false }
        )
        clearDirtyRegions()
        return (outcome.samples, isPartial: partial)
    }

    /// SPK-1700a — same selective resimulation contract as
    /// `performResimulation` but returns the FULL dense `Heightmap` (every
    /// cell — the preview draws a filled raster, not a dot scatter).
    public func performResimulationHeightmap(
        partialLines: [String],
        fullLines: [String],
        sheetWidthMm: Double,
        sheetDepthMm: Double,
        stockTopMm: Double,
        cellSizeMm: Double,
        toolRadiusMm: Double? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) async -> (Heightmap?, isPartial: Bool) {
        guard needsResimulation else {
            return (nil, isPartial: false)
        }

        let isFullTree = dirtyRegions.contains { region in
            if case .fullTree = region { return true }
            if case .keepOutZoneChanged = region { return true }
            return false
        }

        let lines: [String]
        let partial: Bool
        if isFullTree || partialLines.isEmpty {
            lines = fullLines
            partial = false
        } else {
            lines = partialLines
            partial = true
        }
        guard !lines.isEmpty else {
            clearDirtyRegions()
            return (nil, isPartial: partial)
        }

        let outcome = await ToolpathSimulator.simulateHeightmap(
            from: lines,
            sheetWidthMm: sheetWidthMm,
            sheetDepthMm: sheetDepthMm,
            stockTopMm: stockTopMm,
            cellSizeMm: cellSizeMm,
            toolRadiusMm: toolRadiusMm,
            shouldCancel: shouldCancel ?? { false }
        )
        clearDirtyRegions()
        return (outcome.heightmap, isPartial: partial)
    }

    /// Perform full resimulation regardless of dirty state.
    public func performFullResimulation() async {
        markFullTreeDirty()
        let result = await performResimulation(
            partialLines: [], fullLines: [],
            sheetWidthMm: 0, sheetDepthMm: 0, stockTopMm: 0, cellSizeMm: 1
        )
        _ = result
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct DirtyRegionManager_Previews: PreviewProvider {
    static var previews: some View {
        Text("Dirty region manager is a non-visual component")
    }
}
#endif

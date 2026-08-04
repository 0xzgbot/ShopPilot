import Foundation

// MARK: - Toolpath Link Mode

/// Controls whether toolpaths automatically follow their source vectors.
public enum FollowSourceMode {
    /// Toolpaths are independent — changes to vectors don't affect existing toolpaths.
    case manual
    
    /// Toolpaths automatically update when source vectors change (default off).
    case autoFollow
    
    public var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .autoFollow: return "Auto-Follow Source"
        }
    }
}

// MARK: - Toolpath Link

/// Represents a link between a toolpath and its source vectors.
public struct ToolpathLink: Identifiable, Equatable {
    
    public let id = UUID()
    
    /// The ID of the source vector(s) this toolpath is linked to.
    public var sourceVectorIds: [UUID]
    
    /// Whether auto-follow is enabled for this link.
    public var autoFollowEnabled: Bool
    
    /// When the link was last updated.
    public var lastUpdated: Date
    
    /// Whether any of the source vectors are missing.
    public var hasMissingSources: Bool {
        sourceVectorIds.isEmpty
    }
    
    public init(sourceVectorIds: [UUID] = [], autoFollowEnabled: Bool = false) {
        self.sourceVectorIds = sourceVectorIds
        self.autoFollowEnabled = autoFollowEnabled
        self.lastUpdated = Date.now
    }
    
    public static func == (lhs: ToolpathLink, rhs: ToolpathLink) -> Bool {
        lhs.id == rhs.id &&
        lhs.sourceVectorIds == rhs.sourceVectorIds &&
        lhs.autoFollowEnabled == rhs.autoFollowEnabled
    }
}

// MARK: - Link Status

/// The status of a toolpath link.
public enum LinkStatus {
    /// Toolpath is linked to source vectors and up-to-date.
    case linked
    
    /// Toolpath is linked but sources have changed — needs recalculation.
    case stale
    
    /// Toolpath has no source link (manual mode).
    case unlinked
    
    public var displayName: String {
        switch self {
        case .linked: return "Linked"
        case .stale: return "Needs Update"
        case .unlinked: return "Manual"
        }
    }
}

// MARK: - Toolpath Link Manager

/// Manages links between toolpaths and their source vectors.
public final class ToolpathLinkManager: ObservableObject {
    
    @Published public var followSourceMode: FollowSourceMode = .manual
    
    /// Links indexed by toolpath ID.
    private var links: [String: ToolpathLink] = [:]
    
    /// Track which toolpaths need recalculation due to source changes.
    private var staleToolpaths: Set<String> = []
    
    public init() {}
    
    // MARK: - Link Management
    
    /// Create a link between a toolpath and source vectors.
    public func createLink(forToolpathId toolpathId: String, sourceVectorIds: [UUID]) {
        let existing = links[toolpathId] ?? ToolpathLink()
        let newLink = ToolpathLink(
            sourceVectorIds: sourceVectorIds,
            autoFollowEnabled: followSourceMode == .autoFollow || existing.autoFollowEnabled
        )
        links[toolpathId] = newLink
        
        // If in auto-follow mode and sources changed, mark as stale
        if followSourceMode == .autoFollow {
            staleToolpaths.insert(toolpathId)
        } else {
            staleToolpaths.remove(toolpathId)
        }
    }
    
    /// Remove a link for a toolpath.
    public func removeLink(forToolpathId toolpathId: String) {
        links[toolpathId] = nil
        staleToolpaths.remove(toolpathId)
    }
    
    /// Get the link status for a toolpath.
    public func linkStatus(forToolpathId toolpathId: String) -> LinkStatus {
        guard let link = links[toolpathId] else {
            return .unlinked
        }
        
        if staleToolpaths.contains(toolpathId) {
            return .stale
        }
        
        return .linked
    }
    
    /// Check if a toolpath has an active link.
    public func isLinked(toToolpathId toolpathId: String) -> Bool {
        links[toolpathId] != nil && !links[toolpathId]!.sourceVectorIds.isEmpty
    }
    
    /// Get the source vector IDs for a linked toolpath.
    public func sourceVectorIds(forToolpathId toolpathId: String) -> [UUID]? {
        links[toolpathId]?.sourceVectorIds
    }
    
    // MARK: - Auto-Follow
    
    /// Enable or disable auto-follow for a specific link.
    public func setAutoFollow(_ enabled: Bool, forToolpathId toolpathId: String) {
        guard var link = links[toolpathId] else { return }
        link.autoFollowEnabled = enabled
        
        if enabled && staleToolpaths.contains(toolpathId) {
            // Auto-follow is now on — keep it marked as needing update
            // so the next recalculation will pick up changes
        } else if !enabled {
            staleToolpaths.remove(toolpathId)
        }
        
        links[toolpathId] = link
    }
    
    /// Change the global follow source mode.
    public func setFollowSourceMode(_ mode: FollowSourceMode) {
        followSourceMode = mode
        
        // Update all existing links to match new default
        for (toolpathId, _) in links {
            if let link = links[toolpathId] {
                let updatedLink = ToolpathLink(
                    sourceVectorIds: link.sourceVectorIds,
                    autoFollowEnabled: mode == .autoFollow || link.autoFollowEnabled
                )
                links[toolpathId] = updatedLink
                
                if mode == .autoFollow && staleToolpaths.contains(toolpathId) {
                    // Keep stale — needs recalculation with new sources
                } else if mode != .autoFollow {
                    staleToolpaths.remove(toolpathId)
                }
            }
        }
    }
    
    /// Mark a toolpath as up-to-date (sources verified).
    public func markUpToDate(forToolpathId toolpathId: String) {
        staleToolpaths.remove(toolpathId)
        
        if let link = links[toolpathId] {
            var updatedLink = link
            updatedLink.lastUpdated = Date.now
            links[toolpathId] = updatedLink
        }
    }
    
    /// Mark a toolpath as stale (sources changed).
    public func markStale(forToolpathId toolpathId: String) {
        if let link = links[toolpathId], link.autoFollowEnabled || followSourceMode == .autoFollow {
            staleToolpaths.insert(toolpathId)
        }
    }

    /// SPK-0319 lite — call after ANY art edit (vector geometry changed).
    /// Every linked toolpath whose link is in follow mode is marked stale AND
    /// its tree node is marked dirty — so the export gate blocks and the
    /// recalc badge counts it. This NEVER recalculates: recalc stays a
    /// deliberate user action (no silent regeneration).
    public func sourcesDidChange(toolpathTree: ToolpathTreeManager) {
        for (toolpathId, link) in links {
            guard link.autoFollowEnabled || followSourceMode == .autoFollow else { continue }
            staleToolpaths.insert(toolpathId)
            if let id = UUID(uuidString: toolpathId),
               let node = toolpathTree.findNode(id: id) {
                node.markDirty()
            }
        }
    }

    /// Number of links currently in follow mode (autoFollowEnabled or global
    /// autoFollow) — for the UI badge.
    public var activeFollowLinkCount: Int {
        links.values.filter { $0.autoFollowEnabled || followSourceMode == .autoFollow }.count
    }

    /// Get all toolpaths that need recalculation.
    public var staleToolpathIds: [String] {
        Array(staleToolpaths).sorted()
    }
    
    /// Check if any toolpaths are stale.
    public var hasStaleToolpaths: Bool { !staleToolpaths.isEmpty }
}

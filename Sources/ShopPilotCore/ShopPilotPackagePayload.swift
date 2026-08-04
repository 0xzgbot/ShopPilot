import Foundation

// MARK: - Persisted Toolpath

/// Codable snapshot of a toolpath operation for package persistence.
public struct PersistedToolpath: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var toolpathResult: String?
    public var estimatedTimeSeconds: Double
    public var isDirty: Bool
    /// ID of the tool assigned to this operation (nil = none).
    public var toolID: UUID?
    /// Strategy params JSON for this operation (nil = defaults; SPK-1136a).
    public var paramsJSON: String?

    public init(
        id: UUID = UUID(),
        name: String,
        toolpathResult: String? = nil,
        estimatedTimeSeconds: Double = 0,
        isDirty: Bool = false,
        toolID: UUID? = nil,
        paramsJSON: String? = nil
    ) {
        self.id = id
        self.name = name
        self.toolpathResult = toolpathResult
        self.estimatedTimeSeconds = estimatedTimeSeconds
        self.isDirty = isDirty
        self.toolID = toolID
        self.paramsJSON = paramsJSON
    }

    /// Build from a live toolpath tree operation node.
    public init(from node: ToolpathTreeNode) {
        self.id = node.id
        self.name = node.name
        self.toolpathResult = node.toolpathResult
        self.estimatedTimeSeconds = node.estimatedTimeSeconds
        self.isDirty = node.isDirty
        self.toolID = node.toolID
        self.paramsJSON = node.paramsJSON
    }
}

// MARK: - Package Payload

/// Full document payload saved inside a `.shoppilot` package.
public struct ShopPilotPackagePayload: Codable, Sendable {
    public var job: Job
    public var toolpaths: [PersistedToolpath]

    public init(job: Job, toolpaths: [PersistedToolpath] = []) {
        self.job = job
        self.toolpaths = toolpaths
    }

    /// Flat operation list from a toolpath tree manager (root children only).
    public static func toolpaths(from manager: ToolpathTreeManager) -> [PersistedToolpath] {
        manager.root.children.map { PersistedToolpath(from: $0) }
    }

    /// Rebuild a toolpath tree manager from persisted operations.
    public static func restoreToolpathTree(from toolpaths: [PersistedToolpath]) -> ToolpathTreeManager {
        let manager = ToolpathTreeManager()
        for persisted in toolpaths {
            let node = manager.addOperation(persisted.name)
            // addOperation creates a new id; restore persisted fields on that node.
            node.toolpathResult = persisted.toolpathResult
            node.estimatedTimeSeconds = persisted.estimatedTimeSeconds
            node.isDirty = persisted.isDirty
            node.toolID = persisted.toolID
            node.paramsJSON = persisted.paramsJSON
        }
        return manager
    }
}

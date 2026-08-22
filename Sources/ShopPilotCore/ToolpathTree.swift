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

    /// SPK-0316 — the previous computed G-code, kept when a new result is
    /// written so the Preview stage can render an old-vs-new "ghost diff".
    /// Set by `setResult`; nil when the node has never been generated.
    @Published public private(set) var previousResult: String? = nil

    /// SPK-0316 — write a computed result, snapshotting the outgoing value as
    /// `previousResult` (only when it differs, so a no-op regen doesn't
    /// clobber a meaningful old path).
    public func setResult(_ gcode: String?) {
        if let gcode, gcode != toolpathResult {
            previousResult = toolpathResult
        }
        toolpathResult = gcode
        isDirty = false
    }
    
    /// Estimated time for this operation in seconds.
    @Published public var estimatedTimeSeconds: Double = 0.0
    
    /// Whether the node is expanded in the UI.
    @Published public var isExpanded: Bool = false

    /// ID of the tool assigned to this operation (nil = none selected yet).
    /// Resolved against the session's `ToolDatabase` for display/params.
    @Published public var toolID: UUID?

    /// Strategy params for this operation, JSON-encoded (nil = defaults).
    /// Persisted with the document so save/open keeps per-op configuration
    /// (SPK-1136a). Currently populated for Profile operations.
    @Published public var paramsJSON: String?

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

    /// Add a new operation under THIS node (SPK-1204 duplicate uses it to
    /// place the copy under the original's parent).
    @discardableResult
    public func addOperation(_ name: String) -> ToolpathTreeNode {
        let node = ToolpathTreeNode(name: name, type: .operation(name))
        return addChild(node)
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

    /// Strategy classification for a toolpath operation (SPK-1102h-recalc).
    /// Derived from the operation label convention the session uses when
    /// creating ops; `unknown` covers ops the recalc engine can't regenerate.
    public enum StrategyKind: Sendable {
        case profile
        case pocket
        case drill
        case drillBank
        case vcarve
        case rough3D
        case finish3D
        case prism
        case fluting
        case chamfer
        case inlay
        case quickEngrave
        case photoVCarve
        case dragKnife
        case texture
        case sketchCarve
        case rotaryWrap
        case threadMill
        case trochoidSlot
        case unknown

        /// Human-readable strategy name (SPK-1201 cut-layers table column).
        public var displayName: String {
            switch self {
            case .profile: return "Profile"
            case .pocket: return "Pocket"
            case .drill: return "Drill"
            case .drillBank: return "Drill Bank"
            case .vcarve: return "V-Carve"
            case .rough3D: return "Rough 3D"
            case .finish3D: return "Finish 3D"
            case .prism: return "Prism"
            case .fluting: return "Fluting"
            case .chamfer: return "Chamfer"
            case .inlay: return "Inlay"
            case .quickEngrave: return "Quick Engrave"
            case .photoVCarve: return "Photo V-Carve"
            case .dragKnife: return "Drag Knife"
            case .texture: return "Texture"
            case .sketchCarve: return "Sketch Carve"
            case .rotaryWrap: return "Rotary Wrap"
            case .threadMill: return "Thread Mill"
            case .trochoidSlot: return "Trochoid Slot"
            case .unknown: return "Operation"
            }
        }
    }

    /// Whether this node is a Profile operation.
    ///
    /// The tree identifies strategy by the operation label convention the
    /// session uses when creating ops ("Profile …"). Explicit strategy-kind
    /// typing on the node is a SPK-1136 (form-field parity) concern; until
    /// then name-prefix detection is the single source used by
    /// `recalculateDirtyProfiles` and the UI.
    public var isProfileOperation: Bool {
        if case .operation(let label) = type { return label.hasPrefix("Profile") }
        return false
    }

    /// Single source of strategy classification for this node.
    public var strategyKind: StrategyKind {
        guard case .operation(let label) = type else { return .unknown }
        if label.hasPrefix("Profile") { return .profile }
        if label.hasPrefix("Pocket") { return .pocket }
        if label.hasPrefix("Drill Bank") { return .drillBank }
        if label.hasPrefix("Drill") { return .drill }
        if label.hasPrefix("V-Carve") { return .vcarve }
        if label.hasPrefix("Rough 3D") { return .rough3D }
        if label.hasPrefix("Finish 3D") { return .finish3D }
        if label.hasPrefix("Photo V-Carve") { return .photoVCarve }   // relief V-bit raster
        if label.hasPrefix("Prism") { return .prism }
        if label.hasPrefix("Fluting") { return .fluting }
        if label.hasPrefix("Chamfer") { return .chamfer }
        if label.hasPrefix("Inlay") { return .inlay }
        if label.hasPrefix("Quick Engrave") { return .quickEngrave }
        if label.hasPrefix("Drag Knife") { return .dragKnife }
        if label.hasPrefix("Texture") { return .texture }
        if label.hasPrefix("Sketch Carve") { return .sketchCarve }
        if label.hasPrefix("Rotary Wrap") { return .rotaryWrap }
        if label.hasPrefix("Thread Mill") { return .threadMill }
        // SPK-1910b — trochoidal slotting (no prefix collision: "Trochoid"
        // is distinct from "Thread Mill", "Texture", "Profile", …).
        if label.hasPrefix("Trochoid Slot") { return .trochoidSlot }
        return .unknown
    }

    /// The raw strategy label for an operation node (e.g. "Profile"),
    /// or the group label for group nodes.
    public var typeLabel: String {
        switch type {
        case .operation(let label): return label
        case .group(let label): return label
        }
    }

    /// The feed rate (mm/min) from this node's stored params, when the
    /// strategy carries one (SPK-1135 job sheet). Falls back to nil.
    public var paramFeedRate: Double? {
        switch strategyKind {
        case .profile: return profileParams().feedRateMmPerMin
        case .pocket: return pocketParams().feedRateMmPerMin
        case .drill: return drillParams().feedRateMmPerMin
        case .drillBank: return drillBankParams().feedRateMmPerMin
        case .vcarve: return vcarveParams().feedRateMmPerMin
        default: return nil
        }
    }

    /// The spindle RPM from this node's stored params, when the strategy
    /// carries one (SPK-1000 post blocks). Falls back to nil.
    public var paramSpindleRpm: Double? {
        switch strategyKind {
        case .profile: return profileParams().spindleRpm
        case .pocket: return pocketParams().spindleRpm
        case .drill: return drillParams().spindleRpm
        case .drillBank: return drillBankParams().spindleRpm
        case .vcarve: return vcarveParams().spindleRpm
        default: return nil
        }
    }

    /// The cut depth (mm) from this node's stored params, when the strategy
    /// carries one (SPK-1135 job sheet). Falls back to nil.
    public var paramCutDepth: Double? {
        switch strategyKind {
        case .profile: return profileParams().maxDepthOfCutMm
        case .pocket: return pocketParams().maxDepthOfCutMm
        case .drill: return drillParams().cutDepthMm
        case .drillBank: return drillBankParams().cutDepthMm
        case .vcarve: return vcarveParams().maxDepthOfCutMm
        default: return nil
        }
    }

    /// Whether this node is a Pocket operation (label convention, like
    /// `isProfileOperation`).
    public var isPocketOperation: Bool {
        if case .operation(let label) = type { return label.hasPrefix("Pocket") }
        return false
    }

    /// Whether this node is a Drill operation (label convention, like
    /// `isProfileOperation`).
    public var isDrillOperation: Bool {
        if case .operation(let label) = type { return label.hasPrefix("Drill") }
        return false
    }

    /// Whether this node is a V-Carve operation (label convention, like
    /// `isProfileOperation`).
    public var isVCarveOperation: Bool {
        if case .operation(let label) = type { return label.hasPrefix("V-Carve") }
        return false
    }

    /// The V-Carve params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored.
    public func vcarveParams() -> VCarveParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(VCarveParams.self, from: data)
        else {
            return VCarveParams()
        }
        return params
    }

    /// The Drill params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored.
    public func drillParams() -> DrillToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(DrillToolpathParams.self, from: data)
        else {
            return DrillToolpathParams()
        }
        return params
    }

    /// The Drill Bank params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored.
    public func drillBankParams() -> DrillBankToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(DrillBankToolpathParams.self, from: data)
        else {
            return DrillBankToolpathParams()
        }
        return params
    }

    /// The Pocket params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored.
    public func pocketParams() -> PocketToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(PocketToolpathParams.self, from: data)
        else {
            return PocketToolpathParams()
        }
        return params
    }

    /// The Profile params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored.
    public func profileParams() -> ProfileToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(ProfileToolpathParams.self, from: data)
        else {
            return ProfileToolpathParams()
        }
        return params
    }

    /// The Prism params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored (SPK-0900 slice).
    public func prismParams() -> PrismToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(PrismToolpathParams.self, from: data)
        else {
            return PrismToolpathParams()
        }
        return params
    }

    /// The Fluting params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored (SPK-0900 slice).
    public func flutingParams() -> FlutingToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(FlutingToolpathParams.self, from: data)
        else {
            return FlutingToolpathParams()
        }
        return params
    }

    /// The Chamfer params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored (SPK-0900 slice).
    public func chamferParams() -> ChamferToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(ChamferToolpathParams.self, from: data)
        else {
            return ChamferToolpathParams()
        }
        return params
    }

    /// The Inlay params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored (SPK-0802 slice).
    public func inlayParams() -> InlayToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(InlayToolpathParams.self, from: data)
        else {
            return InlayToolpathParams()
        }
        return params
    }

    /// The Quick Engrave params stored on this node (decoded from
    /// `paramsJSON`), or defaults when none are stored (F07 slice).
    public func quickEngraveParams() -> QuickEngraveToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(QuickEngraveToolpathParams.self, from: data)
        else {
            return QuickEngraveToolpathParams()
        }
        return params
    }

    /// The Photo V-Carve params stored on this node (decoded from
    /// `paramsJSON`), or defaults when none are stored (SPK-0901 slice).
    public func photoVCarveParams() -> PhotoVCarveToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(PhotoVCarveToolpathParams.self, from: data)
        else {
            return PhotoVCarveToolpathParams()
        }
        return params
    }

    /// The Drag Knife params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored (SPK-0907 slice).
    public func dragKnifeParams() -> DragKnifeToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(DragKnifeToolpathParams.self, from: data)
        else {
            return DragKnifeToolpathParams()
        }
        return params
    }

    /// The Texture params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored (SPK-0900 slice).
    public func textureParams() -> TextureToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(TextureToolpathParams.self, from: data)
        else {
            return TextureToolpathParams()
        }
        return params
    }

    /// The Sketch Carve params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored (SPK-0901 slice).
    public func sketchCarveParams() -> SketchCarveToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(SketchCarveToolpathParams.self, from: data)
        else {
            return SketchCarveToolpathParams()
        }
        return params
    }

    /// The Rotary Wrap params stored on this node (decoded from `paramsJSON`),
    /// or defaults when none are stored (SPK-0904 slice).
    public func rotaryWrapParams() -> RotaryWrapToolpathParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(RotaryWrapToolpathParams.self, from: data)
        else {
            return RotaryWrapToolpathParams()
        }
        return params
    }

    /// The node's stored thread-mill params (SPK-0902), or defaults when
    /// none were persisted (legacy-safe).
    public func threadMillParams() -> ThreadMillParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(ThreadMillParams.self, from: data)
        else {
            return ThreadMillParams()
        }
        return params
    }

    /// The node's stored trochoid-slot params (SPK-1910b), or defaults when
    /// none were persisted (legacy-safe).
    public func trochoidSlotParams() -> TrochoidSlotParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(TrochoidSlotParams.self, from: data)
        else {
            return TrochoidSlotParams()
        }
        return params
    }

    /// Whether this node is a 3D rough operation (SPK-3D-spine-b).
    public var isRough3DOperation: Bool {
        if case .operation(let label) = type { return label.hasPrefix("Rough 3D") }
        return false
    }

    /// Whether this node is a 3D finish operation (SPK-3D-spine-b).
    public var isFinish3DOperation: Bool {
        if case .operation(let label) = type { return label.hasPrefix("Finish 3D") }
        return false
    }

    /// The rough params stored on this node (decoded from `paramsJSON`), or
    /// defaults when none are stored.
    public func rough3DParams() -> HeightfieldRoughParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(HeightfieldRoughParams.self, from: data)
        else {
            return HeightfieldRoughParams()
        }
        return params
    }

    /// The finish params stored on this node (decoded from `paramsJSON`), or
    /// defaults when none are stored.
    public func finish3DParams() -> HeightfieldFinishParams {
        guard let json = paramsJSON,
              let data = json.data(using: .utf8),
              let params = try? JSONDecoder().decode(HeightfieldFinishParams.self, from: data)
        else {
            return HeightfieldFinishParams()
        }
        return params
    }

    /// Check if any node in the subtree is dirty.
    public var hasDirtyChildren: Bool {
        allDirtyNodes.isEmpty == false
    }
}


// MARK: - Toolpath node result (SPK-1314)

/// A computed toolpath result detached from the tree — the async recalc
/// carries these between the compute pass (any thread) and the apply pass
/// (main actor). Pure value type.
public struct ToolpathNodeResult: Sendable {
    public let nodeID: UUID
    public let gcode: String
    public let estimatedTimeSeconds: Double
    public init(nodeID: UUID, gcode: String, estimatedTimeSeconds: Double) {
        self.nodeID = nodeID
        self.gcode = gcode
        self.estimatedTimeSeconds = estimatedTimeSeconds
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

    /// Find the parent of a node (SPK-1204 duplicate needs the insertion
    /// point). Returns nil for the root / missing nodes.
    public func parent(of id: UUID) -> ToolpathTreeNode? {
        if id == root.id { return nil }
        var result: ToolpathTreeNode? = nil
        func walk(_ node: ToolpathTreeNode) -> Bool {
            for child in node.children {
                if child.id == id {
                    result = node
                    return true
                }
                if walk(child) { return true }
            }
            return false
        }
        _ = walk(root)
        return result
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
            node.setResult("// Toolpath generated for \(node.name)")
            node.isDirty = false
            node.estimatedTimeSeconds = Double.random(in: 10...300)
        }
        
        return dirtyNodes
    }
    
    /// Regenerate every dirty Profile operation with the REAL profile engine
    /// (SPK-1102e). A node's stored params (`paramsJSON`, SPK-1136a) win over
    /// the passed-in defaults when present. Out-of-scope operations
    /// (Pocket/V-Carve…) stay dirty, so export stays blocked on them. Returns
    /// the regenerated nodes in tree order.
    public func recalculateDirtyProfiles(
        vectors: [VectorPath],
        params: ProfileToolpathParams,
        material: Material?,
        stockHeightMm: Double
    ) -> [ToolpathTreeNode] {
        let dirtyProfiles = root.allDirtyNodes.filter { $0.isProfileOperation }
        for node in dirtyProfiles {
            let nodeParams = node.profileParams()
            let result = ProfileToolpathEngine.compute(
                vectors: vectors,
                params: nodeParams,
                material: material,
                stockHeightMm: stockHeightMm
            )
            node.setResult(result.gcodeLines.joined(separator: "\n"))
            node.estimatedTimeSeconds = result.estimatedTimeSeconds
            node.clearDirty()
        }
        return dirtyProfiles
    }

    /// Regenerate EVERY dirty operation with its real engine and the node's
    /// stored params (SPK-1102h-recalc):
    ///   Profile → ProfileToolpathEngine   (stored §R2 params)
    ///   Pocket  → PocketToolpathEngine    (stored §M params)
    ///   Drill   → DrillToolpathEngine     (points from closed-vector
    ///             centroids, stored §N depth/dwell)
    ///   V-Carve → VCarveEngine            (stored §O params)
    /// Ops with no stored params use strategy defaults. When `tools` is
    /// provided and a dirty node has an assigned tool, the tool's linked cut
    /// data (SPK-1133b: resolved geometry → per-material cut data → per-machine
    /// cut data via `material` + `machineName`) replaces the placeholder
    /// defaults (feed 1000, rpm 0) — explicitly configured values (user form
    /// values) are preserved. Unknown ops stay dirty. Returns the regenerated
    /// nodes in tree order.
    public func computeDirtyToolpathResults(
        vectors: [VectorPath],
        material: Material?,
        stockHeightMm: Double,
        tools: [Tool] = [],
        heightfield: HeightfieldData? = nil,
        machineName: String? = nil
    ) -> [ToolpathNodeResult] {
        var results: [ToolpathNodeResult] = []
        let materialName = material?.name
        for node in root.allDirtyNodes {
            switch node.strategyKind {
            case .profile:
                let result = ProfileToolpathEngine.compute(
                    vectors: vectors,
                    params: withToolFeeds(node.profileParams(), node: node, tools: tools, materialName: materialName, machineName: machineName),
                    material: material,
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .pocket:
                let result = PocketToolpathEngine.compute(
                    vectors: vectors,
                    params: withToolFeeds(node.pocketParams(), node: node, tools: tools, materialName: materialName, machineName: machineName),
                    material: material,
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .drill:
                let params = withToolFeeds(node.drillParams(), node: node, tools: tools, materialName: materialName, machineName: machineName)
                let points: [DrillPoint] = vectors.compactMap { path in
                    guard path.isClosed, !path.points.isEmpty else { return nil }
                    let xs = path.points.map(\.x)
                    let ys = path.points.map(\.y)
                    return DrillPoint(
                        x: (xs.min()! + xs.max()!) / 2,
                        y: (ys.min()! + ys.max()!) / 2,
                        zDepthMm: -(params.startDepthMm + params.cutDepthMm),
                        dwellSeconds: params.dwellAtBottom ? params.dwellTimeSeconds : 0
                    )
                }
                guard !points.isEmpty else { continue }
                let result = DrillToolpathEngine.compute(
                    points: points,
                    params: params,
                    material: material,
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .drillBank:
                let params = withToolFeeds(node.drillBankParams(), node: node, tools: tools, materialName: materialName, machineName: machineName)
                // A drill bank is a GRID of holes (params generate the points);
                // selected closed vectors, when present, pin the grid's origin
                // to the selection centroid so the bank sits on the part.
                let points: [DrillPoint]? = {
                    let closed = vectors.filter { $0.isClosed && !$0.points.isEmpty }
                    guard !closed.isEmpty else { return nil }
                    let xs = closed.flatMap { $0.points.map(\.x) }
                    let ys = closed.flatMap { $0.points.map(\.y) }
                    guard let minX = xs.min(), let maxX = xs.max(),
                          let minY = ys.min(), let maxY = ys.max() else { return nil }
                    var centered = params
                    centered.originX += (minX + maxX) / 2
                    centered.originY += (minY + maxY) / 2
                    return centered.gridPoints()
                }()
                let result = DrillBankToolpathEngine.compute(
                    points: points,
                    params: params,
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .vcarve:
                let result = VCarveEngine.compute(
                    vectors: vectors,
                    params: withToolFeeds(node.vcarveParams(), node: node, tools: tools, materialName: materialName, machineName: machineName),
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .rough3D:
                // Needs the imported relief; without one the node stays dirty.
                guard let hf = heightfield else { continue }
                let result = HeightfieldRoughEngine.compute(
                    heightfield: hf,
                    params: withToolFeeds(node.rough3DParams(), node: node, tools: tools, materialName: materialName, machineName: machineName)
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .finish3D:
                guard let hf = heightfield else { continue }
                let result = HeightfieldFinishEngine.compute(
                    heightfield: hf,
                    params: withToolFeeds(node.finish3DParams(), node: node, tools: tools, materialName: materialName, machineName: machineName)
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .prism:
                let result = PrismToolpathEngine.compute(
                    paths: vectors,
                    params: node.prismParams(),
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .fluting:
                let result = FlutingToolpathEngine.compute(
                    paths: vectors,
                    params: node.flutingParams(),
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .chamfer:
                let result = ChamferToolpathEngine.compute(
                    paths: vectors,
                    params: node.chamferParams(),
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .inlay:
                let params = node.inlayParams()
                let result = params.variant == .pocket
                    ? InlayToolpathEngine.computePocket(paths: vectors, params: params, stockHeightMm: stockHeightMm)
                    : InlayToolpathEngine.computePlug(paths: vectors, params: params, stockHeightMm: stockHeightMm)
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .quickEngrave:
                let result = QuickEngraveToolpathEngine.compute(
                    paths: vectors,
                    params: node.quickEngraveParams(),
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .photoVCarve:
                // Needs the imported relief (image or STL); without one the
                // node stays dirty.
                guard let hf = heightfield else { continue }
                let result = PhotoVCarveToolpathEngine.compute(
                    heightfield: hf,
                    params: node.photoVCarveParams()
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .dragKnife:
                let result = DragKnifeToolpathEngine.compute(
                    paths: vectors,
                    params: node.dragKnifeParams(),
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .texture:
                let result = TextureToolpathEngine.compute(
                    paths: vectors,
                    params: node.textureParams(),
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .sketchCarve:
                // Needs the imported relief (image or STL); without one the
                // node stays dirty.
                guard let hf = heightfield else { continue }
                let result = SketchCarveToolpathEngine.compute(
                    heightfield: hf,
                    params: node.sketchCarveParams()
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .rotaryWrap:
                let result = RotaryWrapToolpathEngine.compute(
                    paths: vectors,
                    params: node.rotaryWrapParams(),
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .threadMill:
                // Recompute around the first closed vector's bbox center.
                if let target = vectors.first(where: { $0.isClosed }) {
                    let xs = target.points.map(\.x)
                    let ys = target.points.map(\.y)
                    let cx = (xs.min()! + xs.max()!) / 2
                    let cy = (ys.min()! + ys.max()!) / 2
                    let result = ThreadMillingToolpathEngine.compute(
                        centerX: cx, centerY: cy,
                        params: node.threadMillParams()
                    )
                    results.append(ToolpathNodeResult(
                        nodeID: node.id,
                        gcode: result.gcodeLines.joined(separator: "\n"),
                        estimatedTimeSeconds: result.estimatedTimeSeconds
                    ))
                }

            case .trochoidSlot:
                // SPK-1910b — regenerate the slot corridor from stored params.
                // Too-narrow slots emit header-only G-code; that is a valid
                // (safe) result, so the node still clears its dirty badge.
                let result = TrochoidSlotToolpathEngine.compute(
                    vectors: vectors.filter { $0.isClosed && !$0.points.isEmpty },
                    params: withToolFeeds(node.trochoidSlotParams(), node: node, tools: tools, materialName: materialName, machineName: machineName),
                    material: material,
                    stockHeightMm: stockHeightMm
                )
                results.append(ToolpathNodeResult(
                    nodeID: node.id,
                    gcode: result.gcodeLines.joined(separator: "\n"),
                    estimatedTimeSeconds: result.estimatedTimeSeconds
                ))

            case .unknown:
                continue
            }
        }
        return results
    }
    /// Apply computed results to the tree on the calling (main) actor —
    /// the only place @Published node state may change. Returns the
    /// regenerated nodes (same contract as the old sync recalc).
    public func applyToolpathResults(_ results: [ToolpathNodeResult]) -> [ToolpathTreeNode] {
        var regenerated: [ToolpathTreeNode] = []
        for result in results {
            guard let node = findNode(id: result.nodeID) else { continue }
            node.setResult(result.gcode)
            node.estimatedTimeSeconds = result.estimatedTimeSeconds
            node.clearDirty()
            regenerated.append(node)
        }
        return regenerated
    }

    /// Sync recalc (unchanged contract): compute + apply on the caller thread.
    public func recalculateDirtyToolpaths(
        vectors: [VectorPath],
        material: Material?,
        stockHeightMm: Double,
        tools: [Tool] = [],
        heightfield: HeightfieldData? = nil,
        machineName: String? = nil
    ) -> [ToolpathTreeNode] {
        let results = computeDirtyToolpathResults(
            vectors: vectors,
            material: material,
            stockHeightMm: stockHeightMm,
            tools: tools,
            heightfield: heightfield,
            machineName: machineName
        )
        return applyToolpathResults(results)
    }


    /// SPK-1133b — apply the assigned tool's linked cut data (SPK-1133b:
    /// feed/plunge/rpm from the resolved geometry→material→machine chain) to
    /// params that still carry placeholder defaults (feed 1000, rpm 0).
    /// Explicitly configured values (user form values, or stored values that
    /// were never the placeholder) are preserved.
    private func withToolFeeds<T: ToolFeedApplicable & ToolPassDepthApplicable>(
        _ params: T,
        node: ToolpathTreeNode,
        tools: [Tool],
        materialName: String?,
        machineName: String?
    ) -> T {
        var p = params
        guard let toolID = node.toolID,
              let tool = tools.first(where: { $0.id == toolID }),
              abs(p.feedRateMmPerMin - 1000) < 1e-6 else { return p }
        let resolved = tool.resolvedCutData(material: materialName, machineName: machineName)
        p.feedRateMmPerMin = resolved.feedRateMmPerMin
        p.plungeFeedRateMmPerMin = resolved.plungeRateMmPerMin
        p.spindleRpm = resolved.spindleRpm
        if abs(p.maxDepthOfCutMm - 2.0) < 1e-6 {
            p.maxDepthOfCutMm = resolved.maxDepthOfCutMm
        }
        return p
    }

    /// SPK-1133b — feed/plunge/rpm linkage for strategies without a pass-depth
    /// field (Drill, 3D rough/finish). Depth stays user-controlled there.
    private func withToolFeeds<T: ToolFeedApplicable>(
        _ params: T,
        node: ToolpathTreeNode,
        tools: [Tool],
        materialName: String?,
        machineName: String?
    ) -> T {
        var p = params
        guard let toolID = node.toolID,
              let tool = tools.first(where: { $0.id == toolID }),
              abs(p.feedRateMmPerMin - 1000) < 1e-6 else { return p }
        let resolved = tool.resolvedCutData(material: materialName, machineName: machineName)
        p.feedRateMmPerMin = resolved.feedRateMmPerMin
        p.plungeFeedRateMmPerMin = resolved.plungeRateMmPerMin
        p.spindleRpm = resolved.spindleRpm
        return p
    }
    
    /// Get count of dirty nodes.
    public var dirtyNodeCount: Int {
        root.allDirtyNodes.count
    }
}

// MARK: - Tool feed application (SPK-1133 + SPK-1133b)

/// Strategy params that carry feed/plunge rates the assigned tool can derive,
/// plus (SPK-1133b) a linked spindle RPM the recalc fills from the tool's
/// resolved cut data (0 = not configured → engine emits no S word).
public protocol ToolFeedApplicable {
    var feedRateMmPerMin: Double { get set }
    var plungeFeedRateMmPerMin: Double { get set }
    var spindleRpm: Double { get set }
}

/// Strategy params with a per-pass depth the linked tool cut-data can provide
/// (Profile/Pocket/V-Carve). Strategies without a pass-depth field (Drill,
/// 3D rough/finish) keep their depth user-controlled.
public protocol ToolPassDepthApplicable {
    var maxDepthOfCutMm: Double { get set }
}

extension ProfileToolpathParams: ToolFeedApplicable, ToolPassDepthApplicable {}
extension PocketToolpathParams: ToolFeedApplicable, ToolPassDepthApplicable {}
extension DrillToolpathParams: ToolFeedApplicable {}
extension DrillBankToolpathParams: ToolFeedApplicable {}
extension VCarveParams: ToolFeedApplicable, ToolPassDepthApplicable {}
// SPK-1910b — trochoid slot params carry feed/plunge/rpm for tool linkage.
extension TrochoidSlotParams: ToolFeedApplicable {}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct ToolpathTree_Previews: PreviewProvider {
    static var previews: some View {
        Text("Toolpath tree is a non-visual component")
    }
}
#endif

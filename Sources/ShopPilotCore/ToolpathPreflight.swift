import Foundation

// MARK: - Toolpath Preflight (FM rules, engine layer)

/// Severity for toolpath-level preflight issues (SPK-FM-R013/R014/R019).
public enum ToolpathPreflightSeverity: String, Sendable, Equatable {
    case error
    case warning
}

/// The plain-English fix a preflight issue offers (FM mapping CTAs).
public enum ToolpathPreflightFix: Sendable, Equatable {
    /// Enable the V-Carve flat-bottom floor, prefilled to keep the carve out
    /// of the material's back side (FM-06 / R013).
    case setFlatDepth(recommendedMm: Double)
    /// Auto-place tabs on the through-cut profile (FM-07 / R014).
    case addTabs
    /// Split the multi-tool tree into ordered per-tool files (FM-12 / R019).
    case splitFiles
    /// R017: adopt the measured material thickness into the job (FM-10).
    case useMeasuredValue
    /// Expert dismissal — user accepts the risk (kept session-scoped, same
    /// honesty contract as ExportBlocker's one-shot expert override).
    case warnOnly

    public var title: String {
        switch self {
        case .setFlatDepth: return "Set Flat Depth"
        case .addTabs: return "Add Tabs"
        case .splitFiles: return "Split to Multiple Files"
        case .useMeasuredValue: return "Use Measured Value"
        case .warnOnly: return "Warn Only"
        }
    }

    /// True when this fix is the R013 flat-depth CTA (pattern-match helper —
    /// the enum carries an associated value, so plain == needs this).
    public var isFlatDepthFix: Bool {
        if case .setFlatDepth = self { return true }
        return false
    }

    /// True when this fix is the R014 add-tabs CTA.
    public var isAddTabsFix: Bool {
        if case .addTabs = self { return true }
        return false
    }

    /// True when this fix is the R017 use-measured-value CTA.
    public var isUseMeasuredValueFix: Bool {
        if case .useMeasuredValue = self { return true }
        return false
    }

    /// True when this fix is the R019 split-to-multiple-files CTA.
    public var isSplitFilesFix: Bool {
        if case .splitFiles = self { return true }
        return false
    }
}

/// A single toolpath-level preflight issue found on a tree node.
public struct ToolpathPreflightIssue: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let nodeID: UUID
    public let nodeName: String
    /// Rule id, e.g. "R013" (PREFLIGHT_FM_MAPPING.md).
    public let ruleID: String
    public let severity: ToolpathPreflightSeverity
    /// Plain-English user-facing copy (from the tutor-language table).
    public let message: String
    public let fix: ToolpathPreflightFix

    public init(nodeID: UUID, nodeName: String, ruleID: String,
                severity: ToolpathPreflightSeverity, message: String, fix: ToolpathPreflightFix) {
        self.nodeID = nodeID
        self.nodeName = nodeName
        self.ruleID = ruleID
        self.severity = severity
        self.message = message
        self.fix = fix
    }
}

/// Engine for toolpath-level preflight rules (FM-06/07/12 → R013/R014/R019).
/// Pure functions over tree nodes + params + material — no UI.
public enum ToolpathPreflight {

    /// Safety margin subtracted from the available depth when prefilling the
    /// flat-depth fix (keeps the floor off the material's back side).
    public static let flatDepthSafetyMarginMm: Double = 0.5

    // MARK: - R013 — V-Carve punch-through (FM-06)

    /// Depth the V-bit must reach to span `gapWidth` with a `vBitAngleDegrees`
    /// tool: tipWidth(depth) = 2·depth·tan(halfAngle) → depth = gap / (2·tan(θ/2)).
    public static func maxVDepth(vBitAngleDegrees: Double, gapWidthMm: Double) -> Double {
        let halfAngle = (.pi / 180.0 * vBitAngleDegrees) / 2.0
        return gapWidthMm / (2.0 * tan(halfAngle))
    }

    /// Widest "channel" the carve must bridge: the maximum, over every pair
    /// of vectors, of the nearest-point distance between them. Two parallel
    /// strokes 20mm apart → 20.0; a single vector → 0 (nothing to bridge).
    public static func maxVectorGapWidth(vectors: [VectorPath]) -> Double {
        guard vectors.count >= 2 else { return 0 }
        var widest = 0.0
        for i in 0..<vectors.count {
            let a = vectors[i]
            guard !a.points.isEmpty else { continue }
            for j in (i + 1)..<vectors.count {
                let b = vectors[j]
                guard !b.points.isEmpty else { continue }
                var nearest = Double.greatestFiniteMagnitude
                for pa in a.points {
                    for pb in b.points {
                        let dx = pa.x - pb.x
                        let dy = pa.y - pb.y
                        let d = dx * dx + dy * dy
                        if d < nearest { nearest = d }
                        if nearest == 0 { break }
                    }
                    if nearest == 0 { break }
                }
                if nearest > widest { widest = nearest }
            }
        }
        return sqrt(widest)
    }

    /// R013 check: the tool bridging the widest vector gap would dive deeper
    /// than the material allows (`maxVDepth > materialThickness − startDepth`)
    /// AND the carve has no flat-depth floor (flatBottomMode off) → the bit
    /// punches through the back of the material. Error severity (blocks
    /// export) with a "Set Flat Depth" CTA prefilled to the safe floor.
    public static func vCarvePunchThrough(
        params: VCarveParams,
        vectors: [VectorPath],
        materialThicknessMm: Double,
        startDepthMm: Double = 0,
        nodeID: UUID = UUID(),
        nodeName: String = "V-Carve"
    ) -> ToolpathPreflightIssue? {
        let availableDepth = materialThicknessMm - startDepthMm
        guard availableDepth > 0 else {
            // R009 territory (depth vs stock) — not this rule's job.
            return nil
        }
        let gap = maxVectorGapWidth(vectors: vectors)
        guard gap > 0 else { return nil }
        let depthNeeded = maxVDepth(vBitAngleDegrees: params.vBitAngleDegrees, gapWidthMm: gap)
        guard depthNeeded > availableDepth else { return nil }
        // A flat-bottom floor caps the depth — the carve floors out instead
        // of going through the material.
        if params.flatBottomMode { return nil }

        let recommended = max(0.1, availableDepth - flatDepthSafetyMarginMm)
        return ToolpathPreflightIssue(
            nodeID: nodeID,
            nodeName: nodeName,
            ruleID: "R013",
            severity: .error,
            message: "“\(nodeName)” can go through your material — the V-bit must reach "
                + String(format: "%.1f", depthNeeded) + "mm to span the widest gap, but only "
                + String(format: "%.1f", availableDepth) + "mm is available. Set a flat depth to floor the carve.",
            fix: .setFlatDepth(recommendedMm: recommended)
        )
    }

    // MARK: - R014 — Through-cut without hold-down (FM-07)

    /// R014 check: a profile cut through the full material thickness with no
    /// tabs and no vacuum hold-down will let the part fly out on the last
    /// pass. Warning (override) with an "Add Tabs" CTA.
    public static func throughCutWithoutHoldDown(
        params: ProfileToolpathParams,
        materialThicknessMm: Double,
        vacuumHoldDown: Bool,
        nodeID: UUID = UUID(),
        nodeName: String = "Profile"
    ) -> ToolpathPreflightIssue? {
        guard params.maxDepthOfCutMm >= materialThicknessMm else { return nil }
        if params.addTabs { return nil }
        if vacuumHoldDown { return nil }
        return ToolpathPreflightIssue(
            nodeID: nodeID,
            nodeName: nodeName,
            ruleID: "R014",
            severity: .warning,
            message: "“\(nodeName)” cuts the part free with nothing holding it — "
                + "it can fly out of place on the last pass. Add tabs or use hold-down.",
            fix: .addTabs
        )
    }

    // MARK: - R019 — Multi-tool single-file save without ATC (FM-12)

    /// R019 check: saving toolpaths that use ≥2 distinct tools (an unassigned
    /// node counts as its own bucket) into ONE file is only safe when the post
    /// processor handles tool changes (ATC). GRBL/Universal posts do not →
    /// error (blocks save) with a "Split to Multiple Files" CTA.
    public static func multiToolSingleFile(
        tree: ToolpathTreeManager,
        postSupportsToolChange: Bool,
        nodeID: UUID = UUID(),
        nodeName: String = "Save Toolpaths"
    ) -> ToolpathPreflightIssue? {
        if postSupportsToolChange { return nil }
        let ops = tree.allNodes.filter { $0.isOperation }
        // Set<UUID?> — nil (unassigned tool) is its own bucket.
        let distinctTools = Set(ops.map { $0.toolID })
        guard distinctTools.count >= 2 else { return nil }
        let toolCount = distinctTools.count
        return ToolpathPreflightIssue(
            nodeID: nodeID,
            nodeName: nodeName,
            ruleID: "R019",
            severity: .error,
            message: "These toolpaths use \(toolCount) different tools and the selected post "
                + "processor cannot change tools mid-file. Split to multiple files (ordered) "
                + "or use an ATC post.",
            fix: .splitFiles
        )
    }

    // MARK: - Tree-level runner

    /// Run every toolpath preflight rule over the tree's operation nodes.
    /// `dismissedNodeIDs` are expert overrides already accepted this session
    /// (skipped, matching the 0603 override contract). `vacuumHoldDown` comes
    /// from the active machine profile (R014).
    public static func checkTree(
        _ tree: ToolpathTreeManager,
        vectors: [VectorPath],
        materialThicknessMm: Double,
        dismissedNodeIDs: Set<UUID> = [],
        vacuumHoldDown: Bool = false
    ) -> [ToolpathPreflightIssue] {
        var issues: [ToolpathPreflightIssue] = []
        for node in tree.allNodes {
            guard node.isOperation, !dismissedNodeIDs.contains(node.id) else { continue }
            if node.isVCarveOperation,
               let paramsJSON = node.paramsJSON,
               let paramsData = paramsJSON.data(using: .utf8),
               let params = try? JSONDecoder().decode(VCarveParams.self, from: paramsData) {
                if let issue = vCarvePunchThrough(
                    params: params,
                    vectors: vectors,
                    materialThicknessMm: materialThicknessMm,
                    nodeID: node.id,
                    nodeName: node.name
                ) {
                    issues.append(issue)
                }
            }
            if node.isProfileOperation,
               let paramsJSON = node.paramsJSON,
               let paramsData = paramsJSON.data(using: .utf8),
               let params = try? JSONDecoder().decode(ProfileToolpathParams.self, from: paramsData) {
                if let issue = throughCutWithoutHoldDown(
                    params: params,
                    materialThicknessMm: materialThicknessMm,
                    vacuumHoldDown: vacuumHoldDown,
                    nodeID: node.id,
                    nodeName: node.name
                ) {
                    issues.append(issue)
                }
            }
        }
        return issues
    }
}

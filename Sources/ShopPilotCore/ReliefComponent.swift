import Foundation

// MARK: - Relief component (SPK-0700 lean slice)

/// A 3D relief component: one heightfield plus its combine mode in the
/// document's component stack. This is the LEAN component model — a flat
/// list of heightfield components with per-component combine modes (the full
/// Component/Level tree with opacity/blend stays Phase H). Components
/// composite into the ACTIVE relief (`Job.stlHeightfield`), which the 3D
/// toolpaths (rough/finish/photo/sketch) then cut.
public struct ReliefComponent: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var heightfield: HeightfieldData
    public var combineMode: OperationMode
    public var visible: Bool

    /// SPK-0702 — dynamic component props, applied by `ComponentModifierEngine`
    /// before compositing. Optionals → legacy documents decode unchanged
    /// (synthesized Codable: missing keys decode as nil = no modification).
    public var heightScale: Double?
    public var tiltAngleDegrees: Double?
    public var fadeAmount: Double?
    public var fadeDirection: FadeDirection?

    /// The heightfield with this component's dynamic props applied
    /// (scale → tilt → fade). Used by the compositor; the stored grid stays
    /// pristine so toggling props is always reversible.
    public var modifiedHeightfield: HeightfieldData {
        ComponentModifierEngine.apply(
            heightfield,
            heightScale: heightScale,
            tiltAngleDegrees: tiltAngleDegrees,
            fadeAmount: fadeAmount,
            fadeDirection: fadeDirection
        )
    }

    public init(
        id: UUID = UUID(),
        name: String = "Relief",
        heightfield: HeightfieldData,
        combineMode: OperationMode = .combineAdd,
        visible: Bool = true,
        heightScale: Double? = nil,
        tiltAngleDegrees: Double? = nil,
        fadeAmount: Double? = nil,
        fadeDirection: FadeDirection? = nil
    ) {
        self.id = id
        self.name = name
        self.heightfield = heightfield
        self.combineMode = combineMode
        self.visible = visible
        self.heightScale = heightScale
        self.tiltAngleDegrees = tiltAngleDegrees
        self.fadeAmount = fadeAmount
        self.fadeDirection = fadeDirection
    }
}

// MARK: - Compositor (SPK-0701 lean slice)

/// Real element-wise combine engine over aligned heightfields. The legacy
/// `CombineEngine` in CombineModes.swift only tracks UUIDs and never touches
/// grid data — THIS is the actual math behind Add / Subtract / Merge-high /
/// Low / Max / Min / Multiply.
public enum ComponentCompositor {

    /// Compose the visible components into the active relief, in list order.
    /// Each component's dynamic props (SPK-0702 height/tilt/fade) are applied
    /// first via `modifiedHeightfield`, so modified components composite like
    /// any other grid. Returns nil when no component is visible or the grids
    /// are not aligned (same width/height/cell size/minX/minY — a lean
    /// constraint; mixed grids need resampling which is Phase H).
    public static func composite(_ components: [ReliefComponent]) -> HeightfieldData? {
        var accumulator: HeightfieldData? = nil
        for component in components where component.visible {
            let grid = component.modifiedHeightfield
            guard let acc = accumulator else {
                accumulator = grid
                continue
            }
            guard let merged = combine(acc, grid, mode: component.combineMode) else {
                return nil
            }
            accumulator = merged
        }
        return accumulator
    }

    /// Combine two aligned heightfields element-wise. Returns nil when the
    /// grids are not aligned.
    public static func combine(
        _ a: HeightfieldData,
        _ b: HeightfieldData,
        mode: OperationMode
    ) -> HeightfieldData? {
        guard a.width == b.width, a.height == b.height,
              abs(a.cellSizeMm - b.cellSizeMm) < 1e-9,
              abs(a.minX - b.minX) < 1e-9, abs(a.minY - b.minY) < 1e-9 else {
            return nil
        }
        let maxH = max(a.maxHeight, b.maxHeight)
        var heights = [Double](repeating: 0, count: a.width * a.height)
        for i in 0..<a.heights.count {
            let ha = a.heights[i]
            let hb = b.heights[i]
            let h: Double
            switch mode {
            case .combineAdd:
                h = min(maxH, ha + hb)              // additive, capped at the tallest input
            case .combineSubtract:
                h = max(0, ha - hb)                 // remove b from a, clamped ≥ 0
            case .combineMerge:
                h = max(ha, hb)                     // merge-high: keep the higher surface
            case .combineLow:
                h = min(ha, hb)                     // low: keep the lower surface
            case .combineMax:
                h = max(ha, hb)
            case .combineMin:
                h = min(ha, hb)
            case .combineMultiply:
                h = maxH > 1e-9 ? min(maxH, ha * hb / maxH) : 0  // normalized product
            }
            heights[i] = max(0, h)
        }
        return HeightfieldData(
            width: a.width, height: a.height,
            cellSizeMm: a.cellSizeMm, minX: a.minX, minY: a.minY,
            heights: heights
        )
    }
}

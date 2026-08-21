import Foundation

// MARK: - Nest Part

/// A single part placed on the stock sheet during nesting.
public struct NestPart: Codable, Equatable {
    
    /// The original shape to be nested.
    public let shape: VectorShape
    
    /// The position where this part is placed (top-left of bounding box).
    public let position: VectorPoint
    
    /// Rotation angle in radians.
    public let rotation: Double
    
    /// Index of this part in the original input array.
    public let index: Int
    
    /// Area of this part.
    public var area: Double {
        shape.area
    }
    
    /// Bounding rectangle of this part at its placed position.
    public var boundingBox: Rect {
        let local: Rect
        switch shape {
        case .line(let s, let e):
            local = Rect(minX: min(s.x, e.x), minY: min(s.y, e.y),
                         maxX: max(s.x, e.x), maxY: max(s.y, e.y))
        case .circle(let c, let r):
            local = Rect(minX: c.x - r, minY: c.y - r,
                         maxX: c.x + r, maxY: c.y + r)
        case .rectangle(let o, let w, let h):
            local = Rect(minX: min(o.x, o.x + w), minY: min(o.y, o.y + h),
                         maxX: max(o.x, o.x + w), maxY: max(o.y, o.y + h))
        case .arc(let c, let r, _, _):
            local = Rect(minX: c.x - r, minY: c.y - r,
                         maxX: c.x + r, maxY: c.y + r)
        case .ellipse(let c, let rx, let ry, _):
            local = Rect(minX: c.x - rx, minY: c.y - ry,
                         maxX: c.x + rx, maxY: c.y + ry)
        case .polygon(let c, let r, _, _):
            local = Rect(minX: c.x - r, minY: c.y - r,
                         maxX: c.x + r, maxY: c.y + r)
        case .star(let c, let outer, _, _, _):
            local = Rect(minX: c.x - outer, minY: c.y - outer,
                         maxX: c.x + outer, maxY: c.y + outer)
        case .freehand(let points):
            guard !points.isEmpty else { return Rect() }
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            local = Rect(minX: xs.min()!, minY: ys.min()!,
                         maxX: xs.max()!, maxY: ys.max()!)
        }
        // Translate local bounds to the placed position.
        return Rect(
            minX: local.minX + position.x,
            minY: local.minY + position.y,
            maxX: local.maxX + position.x,
            maxY: local.maxY + position.y
        )
    }
    
    public init(shape: VectorShape, position: VectorPoint, rotation: Double, index: Int) {
        self.shape = shape
        self.position = position
        self.rotation = rotation
        self.index = index
    }
}

// MARK: - Nest Result

/// Result of a nesting operation.
public struct NestResult: Codable {
    
    /// The placed parts.
    public let parts: [NestPart]
    
    /// Total area of all parts.
    public let totalPartArea: Double
    
    /// Total area of the stock sheet.
    public let sheetArea: Double
    
    /// Utilization percentage (0.0–1.0).
    public let utilization: Double
    
    /// Number of parts that could not be placed.
    public let unplacedCount: Int
    
    public var isEmpty: Bool { parts.isEmpty }
    
    public init(parts: [NestPart], totalPartArea: Double, sheetArea: Double, utilization: Double, unplacedCount: Int) {
        self.parts = parts
        self.totalPartArea = totalPartArea
        self.sheetArea = sheetArea
        self.utilization = utilization
        self.unplacedCount = unplacedCount
    }
}

// MARK: - Nesting Engine

/// Simple rectangular packing algorithm for nesting parts on a stock sheet.
///
/// Algorithm:
/// 1. Compute bounding box for each part
/// 2. Sort parts by area (largest first)
/// 3. For each part, try to place it at the first available position
///    that doesn't overlap with existing parts
/// 4. Track remaining free space as rectangular regions
/// 5. Return utilization percentage
public struct NestingEngine {
    
    /// Nest parts on a rectangular stock sheet.
    ///
    /// - Parameters:
    ///   - parts: Array of VectorShape to nest.
    ///   - sheetWidth: Width of the stock sheet in mm.
    ///   - sheetHeight: Height of the stock sheet in mm.
    ///   - margin: Minimum margin around the sheet edge in mm.
    /// - Returns: NestResult with placed parts and utilization.
    public static func nest(
        parts: [VectorShape],
        sheetWidth: Double,
        sheetHeight: Double,
        margin: Double = 5.0
    ) -> NestResult {
        
        guard !parts.isEmpty else {
            return NestResult(
                parts: [],
                totalPartArea: 0,
                sheetArea: sheetWidth * sheetHeight,
                utilization: 0.0,
                unplacedCount: 0
            )
        }
        
        let usableWidth = sheetWidth - 2 * margin
        let usableHeight = sheetHeight - 2 * margin
        
        // Compute bounding boxes and sort by area (largest first)
        var indexedParts: [(shape: VectorShape, bb: Rect, area: Double, index: Int)] = []
        for (i, part) in parts.enumerated() {
            let bb = part.boundingRect
            indexedParts.append((part, bb, part.area, i))
        }
        
        // Sort by area descending
        indexedParts.sort { $0.area > $1.area }
        
        // Free space regions (start with one big region)
        var freeSpaces: [Rect] = [
            Rect(minX: margin, minY: margin,
                 maxX: margin + usableWidth, maxY: margin + usableHeight)
        ]
        
        var placedParts: [NestPart] = []
        var totalPlacedArea: Double = 0
        var unplacedCount = 0
        
        for indexedPart in indexedParts {
            let shape = indexedPart.shape
            let partBB = indexedPart.bb
            let partWidth = partBB.width
            let partHeight = partBB.height
            
            // Try to find a free space that fits this part
            var placed = false
            for spaceIdx in 0..<freeSpaces.count {
                let space = freeSpaces[spaceIdx]
                
                // Check if part fits in this space (try both orientations)
                if partWidth <= space.width && partHeight <= space.height {
                    // Place the part at the top-left of this free space
                    let position = VectorPoint(x: space.minX, y: space.minY)
                    
                    let nestPart = NestPart(
                        shape: shape,
                        position: position,
                        rotation: 0,
                        index: indexedPart.index
                    )
                    
                    placedParts.append(nestPart)
                    totalPlacedArea += indexedPart.area
                    placed = true
                    
                    // Split the remaining free space into two rectangles:
                    // 1. Right of the part
                    // 2. Below the part
                    let rightSpaceX = space.minX + partWidth
                    let rightSpaceWidth = space.width - partWidth
                    
                    if rightSpaceWidth > 0 {
                        freeSpaces.append(
                            Rect(minX: rightSpaceX, minY: space.minY,
                                 maxX: space.maxX, maxY: space.minY + partHeight)
                        )
                    }
                    
                    let belowSpaceY = space.minY + partHeight
                    let belowSpaceHeight = space.height - partHeight
                    
                    if belowSpaceHeight > 0 {
                        freeSpaces.append(
                            Rect(minX: space.minX, minY: belowSpaceY,
                                 maxX: space.maxX, maxY: space.maxY)
                        )
                    }
                    
                    // Remove the used space
                    freeSpaces.remove(at: spaceIdx)
                    
                    break
                } else if partHeight <= space.width && partWidth <= space.height {
                    // Try rotated orientation (90 degrees)
                    let position = VectorPoint(x: space.minX, y: space.minY)
                    
                    let nestPart = NestPart(
                        shape: shape,
                        position: position,
                        rotation: .pi / 2.0,
                        index: indexedPart.index
                    )
                    
                    placedParts.append(nestPart)
                    totalPlacedArea += indexedPart.area
                    placed = true
                    
                    // Split remaining space
                    let belowSpaceY = space.minY + partWidth
                    let belowSpaceHeight = space.height - partWidth
                    
                    if belowSpaceHeight > 0 {
                        freeSpaces.append(
                            Rect(minX: space.minX, minY: belowSpaceY,
                                 maxX: space.maxX, maxY: space.maxY)
                        )
                    }
                    
                    let rightSpaceX = space.minX + partHeight
                    let rightSpaceWidth = space.width - partHeight
                    
                    if rightSpaceWidth > 0 {
                        freeSpaces.append(
                            Rect(minX: rightSpaceX, minY: space.minY,
                                 maxX: space.maxX, maxY: space.minY + partWidth)
                        )
                    }
                    
                    freeSpaces.remove(at: spaceIdx)
                    
                    break
                }
            }
            
            if !placed {
                unplacedCount += 1
            }
        }
        
        let totalSheetArea = sheetWidth * sheetHeight
        let utilization = totalSheetArea > 0 ? totalPlacedArea / totalSheetArea : 0.0
        
        return NestResult(
            parts: placedParts,
            totalPartArea: totalPlacedArea,
            sheetArea: totalSheetArea,
            utilization: utilization,
            unplacedCount: unplacedCount
        )
    }
    
    /// Nest parts with a simple grid-based placement.
    ///
    /// This is a faster but less optimal alternative to the full packing algorithm.
    /// Parts are placed in a grid pattern, row by row.
    ///
    /// - Parameters:
    ///   - parts: Array of VectorShape to nest.
    ///   - sheetWidth: Width of the stock sheet in mm.
    ///   - sheetHeight: Height of the stock sheet in mm.
    ///   - spacing: Minimum spacing between parts in mm.
    /// - Returns: NestResult with placed parts and utilization.
    public static func nestGrid(
        parts: [VectorShape],
        sheetWidth: Double,
        sheetHeight: Double,
        spacing: Double = 2.0
    ) -> NestResult {
        
        guard !parts.isEmpty else {
            return NestResult(
                parts: [],
                totalPartArea: 0,
                sheetArea: sheetWidth * sheetHeight,
                utilization: 0.0,
                unplacedCount: 0
            )
        }
        
        // Compute bounding boxes
        var partBounds: [(bb: Rect, area: Double, index: Int)] = []
        for (i, part) in parts.enumerated() {
            let bb = part.boundingRect
            partBounds.append((bb, part.area, i))
        }
        
        // Sort by width descending (largest first for grid)
        partBounds.sort { $0.bb.width > $1.bb.width }
        
        var placedParts: [NestPart] = []
        var unplacedCount = 0
        var totalPlacedArea: Double = 0
        
        var cursorX = 0.0
        var cursorY = 0.0
        var rowHeight = 0.0
        
        for partBound in partBounds {
            let bb = partBound.bb
            let width = bb.width
            let height = bb.height
            
            // Check if part fits at current cursor position
            if cursorX + width > sheetWidth || cursorY + height > sheetHeight {
                // Move to next row
                cursorX = 0.0
                cursorY += rowHeight + spacing
                rowHeight = height
                
                if cursorY + height > sheetHeight {
                    unplacedCount += 1
                    continue
                }
            }
            
            let position = VectorPoint(x: cursorX, y: cursorY)
            
            let nestPart = NestPart(
                shape: parts[partBound.index],
                position: position,
                rotation: 0,
                index: partBound.index
            )
            
            placedParts.append(nestPart)
            totalPlacedArea += partBound.area
            cursorX += width + spacing
            rowHeight = max(rowHeight, height)
        }
        
        let totalSheetArea = sheetWidth * sheetHeight
        let utilization = totalSheetArea > 0 ? totalPlacedArea / totalSheetArea : 0.0
        
        return NestResult(
            parts: placedParts,
            totalPartArea: totalPlacedArea,
            sheetArea: totalSheetArea,
            utilization: utilization,
            unplacedCount: unplacedCount
        )
    }
}

// MARK: - SPK-1900f: Deterministic skyline packer (rect parts, spacing-aware)
//
// The SPK-1900f card adds a second, rect-part nesting contract alongside the
// legacy VectorShape packer above. Both live on the same `NestingEngine` type:
// `nest(parts:options:)` is the new skyline API, `nest(parts:sheetWidth:)` the
// legacy one — argument labels disambiguate, so existing callers
// (AppSession.nestSelectedShapes, ShopPilotVerify0804) are untouched.

// MARK: - Nesting Part

/// A rectangular part to be nested onto a sheet.
public struct NestingPart: Sendable {
    public let id: UUID
    public let widthMm: Double
    public let heightMm: Double
    public let allowRotation: Bool

    public init(id: UUID, widthMm: Double, heightMm: Double, allowRotation: Bool) {
        self.id = id
        self.widthMm = widthMm
        self.heightMm = heightMm
        self.allowRotation = allowRotation
    }
}

// MARK: - Placement

/// One part's resolved position on the sheet.
///
/// The placed rectangle occupies `x ..< x + w`, `y ..< y + h` in sheet
/// millimetres, where `w`/`h` are the part's `widthMm`/`heightMm` — swapped
/// when `rotated90` is true (rotation is 90° only).
public struct NestedPlacement: Sendable, Equatable {
    public let partID: UUID
    public let xMm: Double
    public let yMm: Double
    public let rotated90: Bool

    public init(partID: UUID, xMm: Double, yMm: Double, rotated90: Bool) {
        self.partID = partID
        self.xMm = xMm
        self.yMm = yMm
        self.rotated90 = rotated90
    }
}

// MARK: - Options

/// Sheet + spacing configuration for a nesting run.
public struct NestingOptions: Sendable {
    public let sheetWidthMm: Double
    public let sheetHeightMm: Double
    /// Margin enforced BOTH part-to-part AND part-to-edge, in millimetres.
    public let spacingMm: Double
    /// Master switch; a part still needs `allowRotation` individually.
    public let allowRotationGlobally: Bool

    public init(
        sheetWidthMm: Double,
        sheetHeightMm: Double,
        spacingMm: Double = 6.0,
        allowRotationGlobally: Bool = true
    ) {
        self.sheetWidthMm = sheetWidthMm
        self.sheetHeightMm = sheetHeightMm
        self.spacingMm = spacingMm
        self.allowRotationGlobally = allowRotationGlobally
    }
}

// MARK: - Result

public enum NestingResult: Sendable {
    case success(placements: [NestedPlacement], usedAreaFraction: Double)
    case doesNotFit(unplacedIDs: [UUID])
}

// MARK: - Engine

/// Deterministic skyline ("shelf") rectangle packer.
///
/// ## Spacing math (exact contract)
///
/// Spacing is enforced by *inflation*, so the invariant holds by construction:
///
///  - Every part's effective footprint is inflated by `spacingMm` on the
///    right and top only: effective size = `(w + s, h + s)` (swapped when
///    rotated). The real part keeps its bottom-left corner at the placement
///    origin, so the extra `s` of inflated footprint forms an empty moat to
///    the right and above the real rectangle.
///  - The sheet is deflated by `spacingMm` on every edge: usable area =
///    `(sheetW − 2s) × (sheetH − 2s)`, with placements offset by `+s` from
///    the sheet origin.
///
/// Consequence: if two inflated footprints never overlap, the real parts are
/// separated by ≥ `s` in at least one axis; and because inflated footprints
/// live inside the deflated sheet, every real edge keeps ≥ `s` margin.
/// Overlap-free is structural, not checked after the fact.
///
/// ## Algorithm
///
///  1. Parts are sorted by max dimension descending, tie-broken by
///     `id.uuidString` ascending — a total order, so any input permutation
///     yields the identical placement sequence (determinism).
///  2. The skyline is a list of `(x, y, width)` segments, initially one
///     segment at y = 0 spanning the usable width.
///  3. Each part tries every skyline segment start as a left-edge candidate,
///     in both orientations when rotation is allowed. A candidate fits when
///     its inflated footprint stays inside the usable area and its base y
///     (max skyline height across the span) plus inflated height stays
///     within the usable height. Among fitting candidates the engine picks
///     bottom-left: minimum base y, then minimum x, then unrotated over
///     rotated (so rotation is only used when it fits strictly lower —
///     "fits at all, else smaller skyline rise").
///  4. Placing raises the skyline across the occupied span to the new top
///     and merges adjacent equal-height segments.
///
/// A part with no fitting candidate in either orientation is reported in
/// `doesNotFit(unplacedIDs:)` (sorted by uuidString); placement of the
/// remaining parts continues so the report is exact.
extension NestingEngine {

    private struct SkylineSegment {
        var x: Double
        var y: Double
        var width: Double
    }

    public static func nest(parts: [NestingPart], options: NestingOptions) -> NestingResult {
        guard !parts.isEmpty else {
            return .success(placements: [], usedAreaFraction: 0)
        }

        let s = options.spacingMm
        let usableWidth = options.sheetWidthMm - 2 * s
        let usableHeight = options.sheetHeightMm - 2 * s
        guard usableWidth > 0, usableHeight > 0 else {
            return .doesNotFit(unplacedIDs: parts.map(\.id).sorted { $0.uuidString < $1.uuidString })
        }

        // Deterministic total order: max dimension desc, then uuidString asc.
        let ordered = parts.sorted { a, b in
            let aMax = max(a.widthMm, a.heightMm)
            let bMax = max(b.widthMm, b.heightMm)
            if aMax != bMax { return aMax > bMax }
            return a.id.uuidString < b.id.uuidString
        }

        var skyline: [SkylineSegment] = [SkylineSegment(x: 0, y: 0, width: usableWidth)]
        var placements: [NestedPlacement] = []
        placements.reserveCapacity(parts.count)
        var unplaced: [UUID] = []

        for part in ordered {
            let canRotate = part.allowRotation && options.allowRotationGlobally
            // Candidate orientations as inflated (effectiveW, effectiveH, rotated).
            var orientations: [(w: Double, h: Double, rotated: Bool)] = [
                (part.widthMm + s, part.heightMm + s, false)
            ]
            if canRotate {
                orientations.append((part.heightMm + s, part.widthMm + s, true))
            }

            // Bottom-left search across segment starts × orientations.
            var best: (x: Double, y: Double, w: Double, h: Double, rotated: Bool)?
            for seg in skyline {
                for o in orientations {
                    guard seg.x + o.w <= usableWidth else { continue }
                    let baseY = skylineHeight(skyline, from: seg.x, span: o.w)
                    guard baseY + o.h <= usableHeight else { continue }
                    // Prefer lower base, then lefter x, then unrotated.
                    let better: Bool
                    if let b = best {
                        better = baseY < b.y
                            || (baseY == b.y && seg.x < b.x)
                            || (baseY == b.y && seg.x == b.x && !o.rotated && b.rotated)
                    } else {
                        better = true
                    }
                    if better {
                        best = (seg.x, baseY, o.w, o.h, o.rotated)
                    }
                }
            }

            guard let chosen = best else {
                unplaced.append(part.id)
                continue
            }

            raiseSkyline(&skyline, x: chosen.x, width: chosen.w, newTop: chosen.y + chosen.h)
            placements.append(
                NestedPlacement(
                    partID: part.id,
                    xMm: chosen.x + s,
                    yMm: chosen.y + s,
                    rotated90: chosen.rotated
                )
            )
        }

        if !unplaced.isEmpty {
            return .doesNotFit(unplacedIDs: unplaced.sorted { $0.uuidString < $1.uuidString })
        }

        let partArea = parts.reduce(0) { $0 + $1.widthMm * $1.heightMm }
        let sheetArea = options.sheetWidthMm * options.sheetHeightMm
        let fraction = sheetArea > 0 ? partArea / sheetArea : 0
        return .success(placements: placements, usedAreaFraction: fraction)
    }

    // MARK: Private helpers

    /// Max skyline height across `[x, x + span)`.
    private static func skylineHeight(_ skyline: [SkylineSegment], from x: Double, span: Double) -> Double {
        let end = x + span
        var height = 0.0
        for seg in skyline {
            let segEnd = seg.x + seg.width
            if segEnd > x && seg.x < end {
                height = max(height, seg.y)
            }
        }
        return height
    }

    /// Raise the skyline over `[x, x + width)` to `newTop`, keeping
    /// neighbouring segments intact and merging equal-height neighbours.
    private static func raiseSkyline(_ skyline: inout [SkylineSegment], x: Double, width: Double, newTop: Double) {
        let xEnd = x + width
        var updated: [SkylineSegment] = []
        for seg in skyline {
            let segEnd = seg.x + seg.width
            if segEnd <= x || seg.x >= xEnd {
                updated.append(seg)
                continue
            }
            if seg.x < x {
                updated.append(SkylineSegment(x: seg.x, y: seg.y, width: x - seg.x))
            }
            if segEnd > xEnd {
                updated.append(SkylineSegment(x: xEnd, y: seg.y, width: segEnd - xEnd))
            }
        }
        updated.append(SkylineSegment(x: x, y: newTop, width: width))
        updated.sort { $0.x < $1.x }

        var merged: [SkylineSegment] = []
        for seg in updated {
            if let last = merged.last, last.x + last.width == seg.x, last.y == seg.y {
                merged[merged.count - 1].width += seg.width
            } else {
                merged.append(seg)
            }
        }
        skyline = merged
    }
}

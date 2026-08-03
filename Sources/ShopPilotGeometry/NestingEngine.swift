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

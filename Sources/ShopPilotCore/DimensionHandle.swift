import Foundation

// MARK: - Dimension handle (SPK-1203)

/// Canvas drag math for a driven dimension — the parametric CAD "editable
/// dimensions" pattern: instead of editing the expression in a panel, drag a
/// control point on the canvas and the dimension's VALUE updates (the
/// expression is replaced by the dragged number; anchor/offset/caption stay).
///
/// The handle is anchored to a world position (e.g. a rectangle's edge), has
/// an offset from the anchor (where the caption line sits), and maps a drag
/// delta in world units to a new value. Pure math — CLT-verifiable; the
/// SwiftUI drag gesture feeds it. Uses Core's `Point2D`.
public struct DimensionHandle: Sendable {
    public let id: UUID
    /// World position the dimension measures from (e.g. the edge midpoint).
    public var anchor: Point2D
    /// Offset from the anchor to the caption (the handle's rest position).
    public var offset: Point2D
    /// Current measured value (mm) — what the drag edits.
    public var value: Double
    /// Axis the drag edits: horizontal drags change the value when true.
    public var isHorizontal: Bool

    public init(id: UUID = UUID(),
                anchor: Point2D,
                offset: Point2D,
                value: Double,
                isHorizontal: Bool = true) {
        self.id = id
        self.anchor = anchor
        self.offset = offset
        self.value = value
        self.isHorizontal = isHorizontal
    }

    /// The handle's rest position in world space (anchor + offset).
    public var position: Point2D {
        Point2D(x: anchor.x + offset.x, y: anchor.y + offset.y)
    }

    /// Apply a drag delta (world units) to the value. The drag axis is the
    /// handle's dimension axis; the perpendicular component moves the handle
    /// (offset) instead, so the caption follows the pointer.
    public mutating func applyDrag(deltaX: Double, deltaY: Double) {
        if isHorizontal {
            value = max(0, value + deltaX)
            offset = Point2D(x: offset.x, y: offset.y + deltaY)
        } else {
            value = max(0, value + deltaY)
            offset = Point2D(x: offset.x + deltaX, y: offset.y)
        }
    }

    /// Build handles for a rectangle's four edges (the common case: driven
    /// width/height of a selected shape). Returns width + height handles.
    public static func handles(forRect minX: Double, minY: Double, maxX: Double, maxY: Double) -> [DimensionHandle] {
        let midX = (minX + maxX) / 2
        let midY = (minY + maxY) / 2
        return [
            DimensionHandle(
                anchor: Point2D(x: midX, y: minY),
                offset: Point2D(x: 0, y: -12),
                value: maxX - minX,
                isHorizontal: true
            ),
            DimensionHandle(
                anchor: Point2D(x: minX, y: midY),
                offset: Point2D(x: -12, y: 0),
                value: maxY - minY,
                isHorizontal: false
            ),
        ]
    }
}

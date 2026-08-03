import Foundation

// MARK: - Create-tool factories (SPK-1120)

/// Factory helpers for the design canvas create tools (rect / circle / line / polyline).
///
/// Each helper takes raw drag endpoints in design coordinates and returns a
/// canonical `VectorShape` ready to insert into the session. The view layer
/// stays free of shape-construction details; the undoable insert itself is
/// owned by `AppSession.addShapes`.
public enum CreateShapes {
    /// Axis-aligned rectangle from a corner drag. The origin is normalized to
    /// the minimum corner so width/height are always non-negative.
    public static func rect(from a: VectorPoint, to b: VectorPoint) -> VectorShape {
        let minX = min(a.x, b.x), maxX = max(a.x, b.x)
        let minY = min(a.y, b.y), maxY = max(a.y, b.y)
        return .rectangle(
            origin: VectorPoint(x: minX, y: minY),
            width: maxX - minX,
            height: maxY - minY
        )
    }

    /// Circle from a center-anchored drag: `a` is the center, `b` the rim
    /// point, so the radius is the distance between the two.
    public static func circle(center a: VectorPoint, through b: VectorPoint) -> VectorShape {
        .circle(center: a, radius: hypot(b.x - a.x, b.y - a.y))
    }

    /// Straight line segment between two drag endpoints.
    public static func line(from a: VectorPoint, to b: VectorPoint) -> VectorShape {
        .line(start: a, end: b)
    }

    /// Polyline from click-placed vertices. Stored as a freehand polyline shape;
    /// the bridge decides open/closed from the vertex list (see `GeometryBridge`).
    public static func polyline(_ points: [VectorPoint]) -> VectorShape {
        .freehand(points: points)
    }
}

import Foundation

/// SPK-1800a: grid-snap math for the Design canvas.
///
/// The canvas grid (`gridLayer`) draws lines every `gridStep` world units;
/// create tools and select-move snap shapes to those same intersections when
/// the toggle is on. Pure helper so both the app target and the CLT share one
/// snap formula.
public enum CanvasSnap {
    /// Round a world-coordinate point to the nearest grid intersection.
    /// When `on` is false, returns `p` unchanged (free placement).
    public static func snap(_ p: CGPoint, gridStep: CGFloat, on: Bool) -> CGPoint {
        guard on else { return p }
        return CGPoint(
            x: round(p.x / gridStep) * gridStep,
            y: round(p.y / gridStep) * gridStep
        )
    }
}

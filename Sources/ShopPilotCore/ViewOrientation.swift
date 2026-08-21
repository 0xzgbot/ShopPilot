import Foundation
import CoreGraphics

// MARK: - View orientation (SPK-1206)

/// View orientation presets for the 3D-ish stages (Preview / Model). The app
/// renders 2D canvas views (no SceneKit renderer yet), so the gizmo drives a
/// 2.5D PROJECTION of the flat world instead of a full 3D camera: the
/// orientation picks a 2D mapping of (x, y) → screen that matches how a
/// top-down / isometric / front camera would see a flat sheet. This is the
/// engine + math; the gizmo overlay is the UI on top.
public enum ViewOrientation: String, CaseIterable, Sendable, Identifiable {
    case top
    case isometric
    case front

    public var id: String { rawValue }

    /// SF Symbol shown on the gizmo face.
    public var icon: String {
        switch self {
        case .top:       return "square.grid.2x2"
        case .isometric: return "cube"
        case .front:     return "rectangle.portrait"
        }
    }

    /// Human label for menus/tooltips.
    public var title: String {
        switch self {
        case .top:       return "Top"
        case .isometric: return "Isometric"
        case .front:     return "Front"
        }
    }
}

/// The 2.5D projection used to map world (x, y) onto the canvas for a given
/// orientation. Pure math — CLT-verifiable.
public struct ViewProjection: Sendable {
    /// Shear applied to X (0 for top-down, 0.707… for isometric).
    public let xShear: Double
    /// Vertical foreshortening (1 for top, 0.5-ish for isometric, 0 for front).
    public let yScale: Double
    /// Perspective foreshortening factor (1 = orthographic; <1 tilts the
    /// sheet away, so far points compress toward the horizon).
    public let perspective: Double

    public static let orthographic = ViewProjection(xShear: 0, yScale: 1, perspective: 1)

    public static func projection(for orientation: ViewOrientation,
                                  orthographic: Bool = true) -> ViewProjection {
        switch orientation {
        case .top:
            return ViewProjection(xShear: 0, yScale: 1, perspective: 1)
        case .isometric:
            // Classic iso: X sheared 45°, Y compressed to 0.577 (30°).
            return ViewProjection(xShear: 0.70710678118,
                                  yScale: orthographic ? 0.57735026919 : 0.5,
                                  perspective: orthographic ? 1 : 0.9)
        case .front:
            // Front view collapses Y (the sheet's depth axis) — you see the
            // thickness edge-on; X stays linear.
            return ViewProjection(xShear: 0, yScale: 0, perspective: 1)
        }
    }

    /// Map a world point to 2.5D screen space.
    public func map(x: Double, y: Double) -> (x: Double, y: Double) {
        let sx = x + y * xShear
        let sy = y * yScale
        if perspective >= 1 { return (sx, sy) }
        // Perspective: compress as the (sheared) depth grows.
        let depth = y * 0.5
        let factor = 1 - (1 - perspective) * min(1, depth)
        return (sx * factor, sy * factor)
    }
}

/// The gizmo's hit-test model: which orientation a click on a cube face
/// selects. The UI maps tap locations to faces; the ENGINE decides the
/// resulting orientation (pure, testable).
public enum GizmoFace: String, Sendable {
    case top, front, right, isometric

    public var orientation: ViewOrientation {
        switch self {
        case .top, .right: return .top
        case .front:       return .front
        case .isometric:   return .isometric
        }
    }
}

/// Convenience for keyboard shortcuts (⌘⌥1…3) and the gizmo menu.
public enum ViewOrientationShortcut {
    public static func orientation(for key: Character) -> ViewOrientation? {
        switch key {
        case "1": return .top
        case "2": return .isometric
        case "3": return .front
        default:  return nil
        }
    }
}

// MARK: - Preview camera fit (sheet-centered isometric)

/// Fit + pan so a world AABB (sheet / vectors / toolpath) lands in the
/// **center** of the Preview canvas after 2.5D projection.
///
/// `worldToView` places mapped (0,0) at the viewport center when pan is
/// zero. Sheets live in [0, W] × [0, D], so a zero pan parks the stock in
/// a corner. This helper projects every world point, then chooses scale
/// and pan so the projected centroid sits at the canvas center with padding.
public enum PreviewCameraFit {
    public static func fit(
        worldPoints: [(x: Double, y: Double)],
        projection: ViewProjection,
        viewportWidth: Double,
        viewportHeight: Double,
        paddingFraction: Double = 0.14
    ) -> (scale: Double, panX: Double, panY: Double) {
        guard !worldPoints.isEmpty, viewportWidth > 1, viewportHeight > 1 else {
            return (2.5, 0, 0)
        }
        let mapped = worldPoints.map { projection.map(x: $0.x, y: $0.y) }
        let minMX = mapped.map(\.x).min() ?? 0
        let maxMX = mapped.map(\.x).max() ?? 1
        let minMY = mapped.map(\.y).min() ?? 0
        let maxMY = mapped.map(\.y).max() ?? 1
        let pw = max(maxMX - minMX, 1e-6)
        let ph = max(maxMY - minMY, 1e-6)
        let pad = min(max(paddingFraction, 0), 0.4)
        let availW = viewportWidth * (1 - 2 * pad)
        let availH = viewportHeight * (1 - 2 * pad)
        let scale = min(40.0, max(0.05, min(availW / pw, availH / ph)))
        let cx = (minMX + maxMX) / 2
        let cy = (minMY + maxMY) / 2
        // sx = vw/2 + panX + mx * scale  →  panX = -cx * scale
        // sy = vh/2 + panY - my * scale  →  panY =  cy * scale
        return (scale, -cx * scale, cy * scale)
    }
}

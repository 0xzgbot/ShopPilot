import Foundation

// MARK: - Component modifier engine (SPK-0702: dynamic height / tilt / fade)

/// REAL engine behind the legacy `DynamicHeightModifier` stub (UUID-tracking
/// manager only — this is the math). Applies per-component dynamic props to a
/// heightfield BEFORE compositing, so the document's component stack can
/// carry height-scale / tilt / fade without storing extra grids.
///
/// All ops are grid-preserving: width/height/cellSizeMm/minX/minY never
/// change — only the heights array does. That keeps the compositor's
/// alignment constraint intact (a modified component still composites with
/// its siblings).
public enum ComponentModifierEngine {

    /// Apply height scale (multiply every height, clamped ≥ 0).
    public static func heightScaled(_ hf: HeightfieldData, by scale: Double) -> HeightfieldData {
        guard abs(scale - 1.0) > 1e-9 else { return hf }
        return HeightfieldData(
            width: hf.width, height: hf.height,
            cellSizeMm: hf.cellSizeMm, minX: hf.minX, minY: hf.minY,
            heights: hf.heights.map { max(0, $0 * scale) }
        )
    }

    /// Apply a tilt: rotate the relief about its grid center by
    /// `angleDegrees` (CCW in world space, +y up), re-sampling with bilinear
    /// interpolation onto the SAME grid. Cells that rotate in from outside
    /// the source footprint read as 0 (the relief's edges fade to flat).
    public static func tilted(_ hf: HeightfieldData, by angleDegrees: Double) -> HeightfieldData {
        guard abs(angleDegrees.truncatingRemainder(dividingBy: 360.0)) > 1e-6 else { return hf }
        let theta = angleDegrees * .pi / 180.0
        let cosT = cos(theta)
        let sinT = sin(theta)
        let cx = hf.minX + (Double(hf.width) * hf.cellSizeMm) / 2.0
        let cy = hf.minY + (Double(hf.height) * hf.cellSizeMm) / 2.0
        var out = [Double](repeating: 0, count: hf.heights.count)
        for j in 0..<hf.height {
            for i in 0..<hf.width {
                let wx = hf.minX + (Double(i) + 0.5) * hf.cellSizeMm
                let wy = hf.minY + (Double(j) + 0.5) * hf.cellSizeMm
                // Inverse-rotate the sample point about the center.
                let dx = wx - cx
                let dy = wy - cy
                let sx = cx + dx * cosT + dy * sinT
                let sy = cy - dx * sinT + dy * cosT
                out[j * hf.width + i] = sample(hf, worldX: sx, worldY: sy)
            }
        }
        return HeightfieldData(
            width: hf.width, height: hf.height,
            cellSizeMm: hf.cellSizeMm, minX: hf.minX, minY: hf.minY,
            heights: out
        )
    }

    /// Apply a directional fade: multiply heights by a ramp from 1.0 at the
    /// "full" edge down to `1 - fadeAmount` at the opposite edge. `fadeAmount`
    /// is clamped to [0, 1]; 0 = no-op.
    public static func faded(
        _ hf: HeightfieldData,
        amount: Double,
        direction: FadeDirection
    ) -> HeightfieldData {
        let amt = min(1.0, max(0.0, amount))
        guard amt > 1e-9, direction != .none else { return hf }
        let w = Double(hf.width)
        let h = Double(hf.height)
        let cx = (w - 1) / 2.0
        let cy = (h - 1) / 2.0
        var out = hf.heights
        for j in 0..<hf.height {
            for i in 0..<hf.width {
                let factor: Double
                switch direction {
                case .none:
                    factor = 1.0
                case .leftToRight:
                    factor = 1.0 - amt * (w > 1 ? Double(i) / (w - 1) : 0)
                case .rightToLeft:
                    factor = 1.0 - amt * (w > 1 ? (w - 1 - Double(i)) / (w - 1) : 0)
                case .topToBottom:
                    factor = 1.0 - amt * (h > 1 ? Double(j) / (h - 1) : 0)
                case .bottomToTop:
                    factor = 1.0 - amt * (h > 1 ? (h - 1 - Double(j)) / (h - 1) : 0)
                case .centerOut:
                    let nx = w > 1 ? abs(Double(i) - cx) / max(cx, 1) : 0
                    let ny = h > 1 ? abs(Double(j) - cy) / max(cy, 1) : 0
                    factor = 1.0 - amt * min(1.0, max(nx, ny))
                case .radial:
                    let nx = w > 1 ? (Double(i) - cx) / max(cx, 1) : 0
                    let ny = h > 1 ? (Double(j) - cy) / max(cy, 1) : 0
                    factor = 1.0 - amt * min(1.0, sqrt(nx * nx + ny * ny))
                }
                out[j * hf.width + i] = max(0, hf.heights[j * hf.width + i] * factor)
            }
        }
        return HeightfieldData(
            width: hf.width, height: hf.height,
            cellSizeMm: hf.cellSizeMm, minX: hf.minX, minY: hf.minY,
            heights: out
        )
    }

    /// Apply all three props in order: scale → tilt → fade. Nil props are
    /// skipped. The identity case (all nil/default) returns the input grid.
    public static func apply(
        _ hf: HeightfieldData,
        heightScale: Double?,
        tiltAngleDegrees: Double?,
        fadeAmount: Double?,
        fadeDirection: FadeDirection?
    ) -> HeightfieldData {
        var out = hf
        if let scale = heightScale {
            out = heightScaled(out, by: scale)
        }
        if let tilt = tiltAngleDegrees {
            out = tilted(out, by: tilt)
        }
        if let amount = fadeAmount, let dir = fadeDirection {
            out = faded(out, amount: amount, direction: dir)
        }
        return out
    }

    // MARK: - Bilinear sampling

    /// Bilinear sample of the heightfield at a world coordinate. Outside the
    /// footprint reads 0 (rotated-in emptiness is flat).
    private static func sample(_ hf: HeightfieldData, worldX: Double, worldY: Double) -> Double {
        let fx = (worldX - hf.minX) / hf.cellSizeMm - 0.5
        let fy = (worldY - hf.minY) / hf.cellSizeMm - 0.5
        guard fx >= -1e-9, fy >= -1e-9, fx <= Double(hf.width - 1) + 1e-9, fy <= Double(hf.height - 1) + 1e-9 else {
            return 0
        }
        let x0 = Int(fx)
        let y0 = Int(fy)
        let x1 = min(x0 + 1, hf.width - 1)
        let y1 = min(y0 + 1, hf.height - 1)
        let tx = fx - Double(x0)
        let ty = fy - Double(y0)
        let h00 = hf.heights[y0 * hf.width + x0]
        let h10 = hf.heights[y0 * hf.width + x1]
        let h01 = hf.heights[y1 * hf.width + x0]
        let h11 = hf.heights[y1 * hf.width + x1]
        let top = h00 + (h10 - h00) * tx
        let bottom = h01 + (h11 - h01) * tx
        return max(0, top + (bottom - top) * ty)
    }
}

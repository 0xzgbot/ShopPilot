import Foundation

// MARK: - Keyhole gadget (H02 lean slice, SPK-0907)

/// Generates a keyhole-slot vector for wall-hanging mounts: a circle for the
/// screw head plus a tangent slot for the shaft. The result is a closed
/// freehand polyline ready for a profile cut.
public enum KeyholeGadget {

    /// Build a keyhole shape. The circle radius derives from the screw head
    /// diameter (+ clearance); the slot half-width from the shaft diameter
    /// (+ clearance). Classic construction: the circle's bottom is tangent to
    /// the slot bottom (circle centre at y = headR), so the head seats in the
    /// circle and the narrower slot retains it when hung.
    /// - Parameters:
    ///   - centerX: X of the keyhole centre line (slot bottom sits at y = 0).
    ///   - screwHeadDiameterMm: screw head / hanger diameter.
    ///   - shaftDiameterMm: screw shaft diameter (slot width).
    ///   - clearanceMm: extra room on both head and shaft.
    /// - Returns: closed freehand polyline (first == last), or nil when the
    ///   shaft is wider than the head (degenerate).
    public static func keyholePath(
        centerX: Double = 0,
        screwHeadDiameterMm: Double,
        shaftDiameterMm: Double,
        clearanceMm: Double = 0.5
    ) -> [VectorPoint]? {
        let headR = max(0.5, screwHeadDiameterMm / 2 + clearanceMm)
        let halfW = max(0.25, shaftDiameterMm / 2 + clearanceMm)
        guard halfW < headR else { return nil }   // shaft can't exceed head
        let centerY = headR                       // circle bottom at y = 0

        var points: [VectorPoint] = []
        // Slot: bottom-left → top-left (slot top reaches the circle centre).
        points.append(VectorPoint(x: centerX - halfW, y: 0))
        points.append(VectorPoint(x: centerX - halfW, y: centerY))
        // Circle arc: from 180° over the TOP to 0° (via 90°), 24 samples.
        let arcSteps = 24
        for k in 1...arcSteps {
            let angle = .pi - .pi * Double(k) / Double(arcSteps)   // π → 0
            points.append(VectorPoint(
                x: centerX + headR * cos(angle),
                y: centerY + headR * sin(angle)
            ))
        }
        // Slot: top-right → bottom-right, close along the bottom.
        points.append(VectorPoint(x: centerX + halfW, y: centerY))
        points.append(VectorPoint(x: centerX + halfW, y: 0))
        points.append(VectorPoint(x: centerX - halfW, y: 0))
        return points
    }

    /// Keyhole as a closed `VectorShape` (ready for `addShapes`).
    public static func keyholeShape(
        centerX: Double = 0,
        screwHeadDiameterMm: Double,
        shaftDiameterMm: Double,
        clearanceMm: Double = 0.5
    ) -> VectorShape? {
        guard let points = keyholePath(
            centerX: centerX,
            screwHeadDiameterMm: screwHeadDiameterMm,
            shaftDiameterMm: shaftDiameterMm,
            clearanceMm: clearanceMm
        ) else { return nil }
        return .freehand(points: points)
    }
}

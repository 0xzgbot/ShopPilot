import Foundation
import ShopPilotCore

// MARK: - Fit Curves Params

/// Parameters controlling the fit-curves (smoothing) pass over a polyline.
///
/// - `smoothing` is 0..1: 0 keeps the polyline exactly as-is, 1 applies
///   maximal smoothing (larger moving-average window + extra pass).
/// - `cornerAngleDegrees` is the direction-change threshold: any interior
///   point whose turn angle is sharper (larger) than this is preserved as a
///   hard corner and never moved by smoothing.
/// - `maxSegmentLengthMm`, when > 0, subdivides segments longer than that
///   length before fitting (optional resampling).
public struct FitCurvesParams: Codable, Sendable {
    /// 0..1 — 0 keeps the polyline as-is, 1 applies maximal smoothing.
    public var smoothing: Double
    /// Direction changes sharper than this (degrees) are kept as hard corners.
    public var cornerAngleDegrees: Double
    /// If > 0, segments longer than this (mm) are subdivided before fitting.
    public var maxSegmentLengthMm: Double

    public init(
        smoothing: Double = 0.5,
        cornerAngleDegrees: Double = 60,
        maxSegmentLengthMm: Double = 0
    ) {
        self.smoothing = smoothing
        self.cornerAngleDegrees = cornerAngleDegrees
        self.maxSegmentLengthMm = maxSegmentLengthMm
    }
}

// MARK: - Fit Curves Result

/// Result of a fit-curves pass over a single shape.
public struct FitCurvesResult: Codable, Sendable {
    /// Number of points in the polyline that was fitted
    /// (after shape sampling / optional resampling).
    public let inputPointCount: Int
    /// Number of points in the fitted polyline.
    public let outputPointCount: Int
    /// Number of hard corners preserved during fitting.
    public let cornerCount: Int
    /// One fitted polyline per input shape (control points of the fit).
    public let fitted: [[VectorPoint]]

    public init(
        inputPointCount: Int,
        outputPointCount: Int,
        cornerCount: Int,
        fitted: [[VectorPoint]]
    ) {
        self.inputPointCount = inputPointCount
        self.outputPointCount = outputPointCount
        self.cornerCount = cornerCount
        self.fitted = fitted
    }
}

// MARK: - Fit Curves Engine

/// Fits smooth curves through polylines while preserving sharp corners.
///
/// Scope: freehand/open polylines. Every other `VectorShape` case is sampled
/// into a polyline first — circles/ellipses into 64 points (closed with an
/// explicit duplicate), polygons into their vertex count, stars into `2 ×
/// points`, rectangles into 4 corners, arcs into 16 points, lines into 2
/// points — and then run through the same corner-preserving pipeline.
///
/// Pipeline per polyline:
/// 1. Optional resampling of segments longer than `maxSegmentLengthMm`.
/// 2. Corner detection: an interior point whose direction change (angle
///    between the incoming and outgoing segment, via the dot product) exceeds
///    `cornerAngleDegrees` is a hard corner.
/// 3. Moving-average smoothing of the points *between* corners only; corner
///    points (and polyline endpoints) are never moved. Window and pass count
///    scale with `smoothing` (window = 1 + Int(smoothing * 4), 1..2 passes).
///
/// Degenerate inputs (fewer than 3 points, or all points collinear) pass
/// through unchanged with `cornerCount == 0`.
public enum FitCurvesEngine {

    /// Fit a single shape, returning the smoothed polyline plus diagnostics.
    public static func fit(shape: VectorShape, params: FitCurvesParams) -> FitCurvesResult {
        var polyline = samplePolyline(from: shape)

        // Optional resampling: subdivide segments longer than the limit.
        if params.maxSegmentLengthMm > 0 {
            polyline = resample(polyline, maxSegmentLengthMm: params.maxSegmentLengthMm)
        }

        let inputCount = polyline.count
        guard inputCount >= 3 else {
            // Degenerate (0/1/2-point) inputs pass through unchanged.
            return FitCurvesResult(
                inputPointCount: inputCount,
                outputPointCount: inputCount,
                cornerCount: 0,
                fitted: [polyline]
            )
        }

        let cornerThreshold = params.cornerAngleDegrees * .pi / 180.0
        let corners = findCorners(polyline, thresholdRadians: cornerThreshold)

        // Degenerate: all points collinear → return the polyline unchanged.
        if corners.isEmpty && isAllStraight(polyline) {
            return FitCurvesResult(
                inputPointCount: inputCount,
                outputPointCount: inputCount,
                cornerCount: 0,
                fitted: [polyline]
            )
        }

        let smoothing = min(max(params.smoothing, 0), 1)
        var fitted = polyline
        if smoothing > 0 {
            let window = 1 + Int(smoothing * 4)  // 1..5
            let iterations = smoothing >= 0.75 ? 2 : 1
            fitted = smooth(polyline, window: window, iterations: iterations, corners: corners)
        }

        return FitCurvesResult(
            inputPointCount: inputCount,
            outputPointCount: fitted.count,
            cornerCount: corners.count,
            fitted: [fitted]
        )
    }

    // MARK: - Shape → Polyline Sampling

    /// Convert any shape into the polyline the fitter operates on.
    private static func samplePolyline(from shape: VectorShape) -> [VectorPoint] {
        switch shape {
        case .line(let start, let end):
            return [start, end]
        case .circle(let center, let radius):
            return sampleClosedEllipse(
                center: center, radiusX: radius, radiusY: radius, rotation: 0, count: 64
            )
        case .ellipse(let center, let radiusX, let radiusY, let rotation):
            return sampleClosedEllipse(
                center: center, radiusX: radiusX, radiusY: radiusY,
                rotation: rotation, count: 64
            )
        case .rectangle(let origin, let width, let height):
            return [
                origin,
                VectorPoint(x: origin.x + width, y: origin.y),
                VectorPoint(x: origin.x + width, y: origin.y + height),
                VectorPoint(x: origin.x, y: origin.y + height),
            ]
        case .arc(let center, let radius, let startAngle, let endAngle):
            return sampleArc(
                center: center, radius: radius,
                startAngle: startAngle, endAngle: endAngle, count: 16
            )
        case .polygon(let center, let radius, let sides, let rotation):
            return polygonVertices(center: center, radius: radius, sides: sides, rotation: rotation)
        case .star(let center, let outerRadius, let innerRadius, let points, let rotation):
            return starVertices(
                center: center, outerRadius: outerRadius, innerRadius: innerRadius,
                points: points, rotation: rotation
            )
        case .freehand(let points):
            return points
        }
    }

    /// 63 points around the ellipse plus an explicit closing duplicate
    /// (first == last exactly), totalling `count` points.
    private static func sampleClosedEllipse(
        center: VectorPoint, radiusX: Double, radiusY: Double,
        rotation: Double, count: Int
    ) -> [VectorPoint] {
        guard count >= 3 else { return [] }
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        var points: [VectorPoint] = []
        for i in 0..<(count - 1) {
            let angle = 2.0 * .pi * Double(i) / Double(count - 1)
            let x = radiusX * cos(angle)
            let y = radiusY * sin(angle)
            points.append(VectorPoint(
                x: center.x + x * cosR - y * sinR,
                y: center.y + x * sinR + y * cosR
            ))
        }
        points.append(points[0])  // closing duplicate
        return points
    }

    /// `count` evenly spaced points along the arc (open polyline).
    private static func sampleArc(
        center: VectorPoint, radius: Double,
        startAngle: Double, endAngle: Double, count: Int
    ) -> [VectorPoint] {
        guard count >= 2 else { return [] }
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            let angle = startAngle + (endAngle - startAngle) * t
            return VectorPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }

    // MARK: - Resampling

    /// Subdivide every segment longer than `maxSegmentLengthMm` into equal
    /// parts no longer than the limit. Degenerate/zero-length segments pass
    /// through untouched.
    private static func resample(_ points: [VectorPoint], maxSegmentLengthMm: Double) -> [VectorPoint] {
        guard points.count >= 2, maxSegmentLengthMm > 0 else { return points }
        var out: [VectorPoint] = [points[0]]
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            if length <= maxSegmentLengthMm {
                out.append(b)
                continue
            }
            // Safety cap: pathological tiny limits must not hang the fitter.
            let parts = min(10_000, max(1, Int((length / maxSegmentLengthMm).rounded(.up))))
            for k in 1...parts {
                let t = Double(k) / Double(parts)
                out.append(VectorPoint(x: a.x + dx * t, y: a.y + dy * t))
            }
        }
        return out
    }

    // MARK: - Corner Detection

    /// Interior point indices where the direction change (angle between the
    /// incoming and outgoing segment, via the normalized dot product) exceeds
    /// `thresholdRadians`. Zero-length segments are skipped.
    private static func findCorners(_ points: [VectorPoint], thresholdRadians: Double) -> [Int] {
        guard points.count >= 3 else { return [] }
        var corners: [Int] = []
        for i in 1..<(points.count - 1) {
            let ax = points[i].x - points[i - 1].x
            let ay = points[i].y - points[i - 1].y
            let bx = points[i + 1].x - points[i].x
            let by = points[i + 1].y - points[i].y
            let la = (ax * ax + ay * ay).squareRoot()
            let lb = (bx * bx + by * by).squareRoot()
            guard la > 1e-12, lb > 1e-12 else { continue }
            let dot = (ax * bx + ay * by) / (la * lb)
            let angle = acos(min(1, max(-1, dot)))
            if angle > thresholdRadians {
                corners.append(i)
            }
        }
        return corners
    }

    /// Whether every interior point is exactly (within 1e-9) collinear with
    /// its neighbors — used to short-circuit degenerate inputs.
    private static func isAllStraight(_ points: [VectorPoint]) -> Bool {
        for i in 1..<(points.count - 1) {
            let ax = points[i].x - points[i - 1].x
            let ay = points[i].y - points[i - 1].y
            let bx = points[i + 1].x - points[i].x
            let by = points[i + 1].y - points[i].y
            let la = (ax * ax + ay * ay).squareRoot()
            let lb = (bx * bx + by * by).squareRoot()
            guard la > 1e-12, lb > 1e-12 else { continue }
            let dot = (ax * bx + ay * by) / (la * lb)
            if dot < 1 - 1e-9 {
                return false
            }
        }
        return true
    }

    // MARK: - Smoothing

    /// Moving-average smoothing over `iterations` passes. Only interior,
    /// non-corner points are replaced; corner points and polyline endpoints
    /// stay untouched, and perfectly straight runs stay bit-exact.
    private static func smooth(
        _ points: [VectorPoint], window: Int, iterations: Int, corners: [Int]
    ) -> [VectorPoint] {
        guard points.count >= 3, window >= 2, iterations >= 1 else { return points }
        let cornerSet = Set(corners)
        let half = max(1, (window - 1) / 2)
        var current = points
        for _ in 0..<iterations {
            var next = current
            for i in 1..<(current.count - 1) where !cornerSet.contains(i) {
                // Skip already-perfectly-straight points so collinear runs
                // (and the 3-point collinear case) survive bit-exact.
                if isStraightRun(current, at: i) { continue }
                let lo = max(0, i - half)
                let hi = min(current.count - 1, i + half)
                var sumX = 0.0
                var sumY = 0.0
                var count = 0
                for j in lo...hi {
                    sumX += current[j].x
                    sumY += current[j].y
                    count += 1
                }
                next[i] = VectorPoint(x: sumX / Double(count), y: sumY / Double(count))
            }
            current = next
        }
        return current
    }

    /// Whether the local turn at index `i` is exactly straight (dot ≈ 1).
    private static func isStraightRun(_ points: [VectorPoint], at i: Int) -> Bool {
        let ax = points[i].x - points[i - 1].x
        let ay = points[i].y - points[i - 1].y
        let bx = points[i + 1].x - points[i].x
        let by = points[i + 1].y - points[i].y
        let la = (ax * ax + ay * ay).squareRoot()
        let lb = (bx * bx + by * by).squareRoot()
        guard la > 1e-12, lb > 1e-12 else { return true }
        let dot = (ax * bx + ay * by) / (la * lb)
        return dot >= 1 - 1e-9
    }
}

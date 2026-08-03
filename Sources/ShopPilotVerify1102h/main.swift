import Foundation
@testable import ShopPilotCore

// MARK: - ShopPilotVerify1102h
//
// Verifies SPK-1102h: PocketToolpathEngine spiral-out on a closed rect
// yields non-empty, closed-ish G1 lines (plunge + concentric rings at depth).

func assert(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
    print("PASS: \(message)")
}

// Closed rectangle: 80mm x 60mm, closed polyline.
let points: [VectorPoint] = [
    VectorPoint(x: 0, y: 0),
    VectorPoint(x: 80, y: 0),
    VectorPoint(x: 80, y: 60),
    VectorPoint(x: 0, y: 60),
    VectorPoint(x: 0, y: 0)
]
let rect = VectorPath(name: "Rect", points: points, isClosed: true)

let params = PocketToolpathParams(
    clearanceMode: .spiralOut,
    stepOverMm: 3.0,
    feedRateMmPerMin: 1000,
    plungeFeedRateMmPerMin: 300,
    maxDepthOfCutMm: 2.0,
    toolDiameterMm: 6.0,
    safetyHeightMm: 5.0
)

let result = PocketToolpathEngine.compute(
    vectors: [rect],
    params: params,
    material: nil,
    stockHeightMm: 25.0
)

// AC: spiral-out on a closed rect yields non-empty G1 lines.
let g1Lines = result.gcodeLines.filter { $0.hasPrefix("G1") }
assert(!g1Lines.isEmpty, "spiral-out on closed rect yields non-empty G1 lines (got \(g1Lines.count))")
assert(g1Lines.count >= 30, "spiral-out yields a full ring's worth of G1 lines (got \(g1Lines.count))")

// The first G1 must be the plunge to depth at plunge feed.
guard let firstG1 = g1Lines.first else {
    print("FAIL: expected at least one G1 line")
    exit(1)
}
assert(firstG1.contains("Z-2.000") && firstG1.contains("F300"),
       "first G1 is a plunge to depth at plunge feed (got: \(firstG1))")

// Rings must run at the configured feed rate and form closed-ish loops:
// the first ring starts at angle 0 and sweeps back to angle 2*pi, so its
// last XY point lands on (or within rounding of) its first XY point.
let sweepLines = g1Lines.filter { $0.contains("X") && $0.contains("Y") }
assert(sweepLines.allSatisfy { $0.contains("F1000") },
       "spiral rings use the configured feed rate")

func xy(_ line: String) -> (x: Double, y: Double)? {
    // Lines look like: "G1 X43.000 Y30.000 F1000"
    let parts = line.split(separator: " ")
    guard parts.count >= 3,
          let x = Double(parts[1].dropFirst()),
          let y = Double(parts[2].dropFirst())
    else { return nil }
    return (x, y)
}

// First ring = first (numPoints+1) sweep lines; numPoints = max(8, Int(r*10))
// at the first ring's radius r = toolDiameter/2 = 3.0 -> 30 segments, 31 points.
let ringSpan = 31
guard sweepLines.count >= ringSpan,
      let ringStart = xy(sweepLines[0]),
      let ringEnd = xy(sweepLines[ringSpan - 1])
else {
    print("FAIL: first ring too short to check closure")
    exit(1)
}
let dx = ringStart.x - ringEnd.x
let dy = ringStart.y - ringEnd.y
let dist = (dx * dx + dy * dy).squareRoot()
assert(dist < 0.01, "first spiral ring is closed-ish (start \(ringStart) -> end \(ringEnd), dist \(dist))")

// Ring radii must grow outward from the tool radius: first sweep X starts at
// centerX + toolDiameter/2 (angle 0, smallest ring).
let centerX = 40.0
let centerY = 30.0
assert(abs(ringStart.x - (centerX + 3.0)) < 0.01 && abs(ringStart.y - centerY) < 0.01,
       "first ring sits at tool radius from center (got \(ringStart))")

// A pocket barely larger than the tool must still yield at least one ring
// (regression: previously maxRadius < start radius -> zero G1 lines).
let smallParams = PocketToolpathParams(
    clearanceMode: .spiralOut,
    stepOverMm: 3.0,
    feedRateMmPerMin: 1000,
    plungeFeedRateMmPerMin: 300,
    maxDepthOfCutMm: 2.0,
    toolDiameterMm: 6.0,
    safetyHeightMm: 5.0
)
let smallRect = VectorPath(name: "Small", points: [
    VectorPoint(x: 0, y: 0),
    VectorPoint(x: 10, y: 0),
    VectorPoint(x: 10, y: 10),
    VectorPoint(x: 0, y: 10),
    VectorPoint(x: 0, y: 0)
], isClosed: true)
let smallResult = PocketToolpathEngine.compute(
    vectors: [smallRect],
    params: smallParams,
    material: nil,
    stockHeightMm: 25.0
)
let smallG1 = smallResult.gcodeLines.filter { $0.hasPrefix("G1") && $0.contains("X") && $0.contains("Y") }
assert(!smallG1.isEmpty, "10mm pocket with 6mm tool still emits at least one spiral ring (got \(smallG1.count))")

print("\nShopPilotVerify1102h PASS — spiral-out emits \(g1Lines.count) G1 lines for a rect")

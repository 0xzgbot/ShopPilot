import Foundation
@testable import ShopPilotCore

// MARK: - ShopPilotVerifyProfileToolpath

// Verifies:
// 1. ProfileToolpathEngine.compute for a closed polyline returns non-empty path/G1 segments
// 2. outCut/inCut/onCut modes produce different offsets

func assert(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
    print("PASS: \(message)")
}

// Test 1: Closed polyline onCut produces non-empty path with G1 segments
let points: [VectorPoint] = [
    VectorPoint(x: 0, y: 0),
    VectorPoint(x: 50, y: 0),
    VectorPoint(x: 50, y: 50),
    VectorPoint(x: 0, y: 50),
    VectorPoint(x: 0, y: 0)
]
let vectorPath = VectorPath(points: points, isClosed: true)

let params = ProfileToolpathParams(
    cutMode: .onCut,
    feedRateMmPerMin: 1000,
    plungeFeedRateMmPerMin: 300,
    maxDepthOfCutMm: 2.0,
    toolDiameterMm: 6.0,
    tabWidths: [],
    finishPasses: 1,
    leadInDistanceMm: 5.0,
    leadOutDistanceMm: 5.0
)

let result = ProfileToolpathEngine.compute(
    vectors: [vectorPath],
    params: params,
    material: nil,
    stockHeightMm: 12.0
)

assert(!result.path.isEmpty, "path must be non-empty for closed polyline")
assert(result.path.contains { $0.hasPrefix("G1") }, "path must contain G1 segments")
assert(!result.gcodeLines.isEmpty, "gcodeLines must be non-empty")
assert(result.gcodeLines.contains { $0.hasPrefix("G1") }, "gcodeLines must contain G1 segments")

// Test 2: outCut mode produces different offset than onCut
let outParams = ProfileToolpathParams(
    cutMode: .outCut,
    feedRateMmPerMin: 1000,
    plungeFeedRateMmPerMin: 300,
    maxDepthOfCutMm: 2.0,
    toolDiameterMm: 6.0,
    tabWidths: [],
    finishPasses: 1,
    leadInDistanceMm: 5.0,
    leadOutDistanceMm: 5.0
)

let outResult = ProfileToolpathEngine.compute(
    vectors: [vectorPath],
    params: outParams,
    material: nil,
    stockHeightMm: 12.0
)

assert(!outResult.path.isEmpty, "outCut path must be non-empty")

// Test 3: inCut mode produces different offset than onCut
let inParams = ProfileToolpathParams(
    cutMode: .inCut,
    feedRateMmPerMin: 1000,
    plungeFeedRateMmPerMin: 300,
    maxDepthOfCutMm: 2.0,
    toolDiameterMm: 6.0,
    tabWidths: [],
    finishPasses: 1,
    leadInDistanceMm: 5.0,
    leadOutDistanceMm: 5.0
)

let inResult = ProfileToolpathEngine.compute(
    vectors: [vectorPath],
    params: inParams,
    material: nil,
    stockHeightMm: 12.0
)

assert(!inResult.path.isEmpty, "inCut path must be non-empty")

// Test 4: onCut path should differ from outCut (different offset)
let onGcode = result.gcodeLines.joined(separator: "\n")
let outGcode = outResult.gcodeLines.joined(separator: "\n")
assert(onGcode != outGcode, "onCut and outCut should produce different G-code")

// Test 5: onCut path should differ from inCut
let inGcode = inResult.gcodeLines.joined(separator: "\n")
assert(onGcode != inGcode, "onCut and inCut should produce different G-code")

print("\nAll checks passed.")
print("ShopPilotVerifyProfileToolpath: PASS — profile toolpath engine verified")

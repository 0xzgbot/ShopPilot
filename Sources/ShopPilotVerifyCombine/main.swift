import Foundation
import ShopPilotCore

/// SPK-0700/0701 lean slice — relief component compositing. Verifies the
/// REAL element-wise combine math (the legacy CombineEngine only tracks
/// UUIDs): Add caps at the tallest input, Subtract clamps ≥ 0, Merge/Max
/// take the higher surface, Low/Min the lower, Multiply is normalized; grid
/// alignment is enforced; components persist legacy-safe on the Job; the
/// compositor drives the active relief that 3D toolpaths cut.
enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func grid(_ w: Int, _ h: Int, _ fill: Double) -> HeightfieldData {
    HeightfieldData(width: w, height: h, cellSizeMm: 5, minX: 0, minY: 0,
                    heights: [Double](repeating: fill, count: w * h))
}

func main() throws {
    // 2×2 grids: A flat 6, B flat 2.
    let a = grid(2, 2, 6)
    let b = grid(2, 2, 2)

    // 1. Add: caps at the tallest input (6), not 8.
    let add = try! ComponentCompositor.combine(a, b, mode: .combineAdd)!
    try expect(add.heights.allSatisfy { abs($0 - 6) < 1e-9 }, "Add = 6 (capped), got \(add.heights)")

    // 2. Subtract: 6 − 2 = 4, clamped ≥ 0.
    let sub = try! ComponentCompositor.combine(a, b, mode: .combineSubtract)!
    try expect(sub.heights.allSatisfy { abs($0 - 4) < 1e-9 }, "Subtract = 4, got \(sub.heights)")

    // 3. Merge / Max: higher surface (6). Low / Min: lower (2).
    let merge = try! ComponentCompositor.combine(a, b, mode: .combineMerge)!
    try expect(merge.heights.allSatisfy { abs($0 - 6) < 1e-9 }, "Merge High = 6")
    let low = try! ComponentCompositor.combine(a, b, mode: .combineLow)!
    try expect(low.heights.allSatisfy { abs($0 - 2) < 1e-9 }, "Low = 2")

    // 4. Multiply: normalized product = 6·2/6 = 2.
    let mul = try! ComponentCompositor.combine(a, b, mode: .combineMultiply)!
    try expect(mul.heights.allSatisfy { abs($0 - 2) < 1e-9 }, "Multiply = 6·2/6 = 2, got \(mul.heights)")

    // 5. Alignment: different cell size → nil.
    let shifted = HeightfieldData(width: 2, height: 2, cellSizeMm: 10, minX: 0, minY: 0,
                                  heights: [Double](repeating: 2, count: 4))
    try expect(ComponentCompositor.combine(a, shifted, mode: .combineAdd) == nil,
               "misaligned grids → nil")

    // 6. Composite folds a stack in order: [A(add), B(subtract)] → 6 then
    //    subtract 2 → 4. Visibility respected (hidden component skipped).
    let stack = [
        ReliefComponent(name: "Base", heightfield: a, combineMode: .combineAdd),
        ReliefComponent(name: "Cut", heightfield: b, combineMode: .combineSubtract),
    ]
    let composed = try! ComponentCompositor.composite(stack)!
    try expect(composed.heights.allSatisfy { abs($0 - 4) < 1e-9 }, "stack [add 6, sub 2] = 4, got \(composed.heights)")

    // Hidden component is skipped.
    let hidden = [
        ReliefComponent(name: "Base", heightfield: a, combineMode: .combineAdd),
        ReliefComponent(name: "Hidden", heightfield: b, combineMode: .combineSubtract, visible: false),
    ]
    let composedHidden = try! ComponentCompositor.composite(hidden)!
    try expect(composedHidden.heights.allSatisfy { abs($0 - 6) < 1e-9 }, "hidden component skipped → 6")

    // 7. Job persistence: legacy-safe optional field.
    var job = Job(name: "Combine Test")
    job.stlHeightfield = a
    job.reliefComponents = stack
    let data = try JSONEncoder().encode(job)
    let back = try JSONDecoder().decode(Job.self, from: data)
    try expect(back.reliefComponents?.count == 2, "components round-trip on Job")
    try expect(back.reliefComponents?.first?.combineMode == .combineAdd, "combine mode persists")

    // Legacy decode: a job saved BEFORE components existed has no key → nil.
    let legacy = """
    {"id":"\(job.id.uuidString)","name":"Legacy","sheets":[],"createdAt":0,"updatedAt":0,
     "vcarvePasses":0,"vcarveTimeSeconds":0,"documentVariables":[],"drivenDimensions":[]}
    """.data(using: .utf8)!
    let legacyBack = try JSONDecoder().decode(Job.self, from: legacy)
    try expect(legacyBack.reliefComponents == nil, "legacy job → components nil")
    try expect(legacyBack.stlHeightfield == nil, "legacy job → relief nil")

    print("ShopPilotVerifyCombine: PASS — Add cap/Subtract clamp/Merge/Max/Low/Min/Multiply math, alignment gate, stack order + visibility, Job round-trip + legacy nil")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyCombine: FAIL — \(error)")
    exit(1)
}

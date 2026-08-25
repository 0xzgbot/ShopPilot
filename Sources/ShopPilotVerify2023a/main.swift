import Foundation
import ShopPilotCore

// SPK-2023a verify — chip-load preflight warning (warning tier only).
//
// AC1: seed JSON decodes; pine (softwood alias) + hardwood bands exist.
// AC2: in-range feed → .ok at BOTH range edges (no false positives).
// AC3: out-of-range → .warning naming computed vs recommended.
// AC4: flutes/rpm math asserted — chipload = feed / (rpm × flutes).
// AC5: preset-trusted path (feedsFromPreset, H-501 lineage) skips warning.
// AC6: warning never blocks export/recalc — CHIP-LOAD severity is always
//      .warning with the informational .warnOnly fix; never .error.

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerify2023a: FAIL — \(msg)")
        exit(1)
    }
}

func approxEqual(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool {
    abs(a - b) <= tol
}

// --- AC1: seed decodes; pine + hardwood present ----------------------------
guard let seed = BitFeedsLibrary.loadSeed() else {
    print("ShopPilotVerify2023a: FAIL — bit_feeds_seed.json did not decode")
    exit(1)
}
expect(!seed.materials.isEmpty && !seed.bands.isEmpty, "seed has materials and diameter bands")

let pine = seed.materials.first { $0.matches("pine") }
expect(pine?.name == "softwood", "pine resolves to softwood (alias match)")
let hard = seed.materials.first { $0.matches("Hardwood") }
expect(hard != nil, "hardwood band exists")
expect(seed.materials.contains { $0.matches("walnut") }, "walnut aliases to hardwood")
expect(pine!.matches("PINE"), "alias matching is case-insensitive")
// Diameter bands span 1–6 mm for both required materials.
for mat in ["softwood", "hardwood"] {
    let bands = seed.bands.filter { $0.material == mat }
    expect(bands.count >= 2, "\(mat) has ≥2 diameter bands (got \(bands.count))")
    expect(bands.map(\.bitDiameterMinMm).min() == 1.0, "\(mat) smallest band starts at 1 mm")
    expect(bands.map(\.bitDiameterMaxMm).max() == 6.0, "\(mat) largest band ends at 6 mm")
}

// --- AC4: math asserted (feed / (rpm × flutes)) ----------------------------
let cl = ChipLoadPreflight.chipLoad(feedRateMmPerMin: 1800, rpm: 18000, flutes: 2)
expect(cl != nil && approxEqual(cl!, 1800.0 / (18000.0 * 2)), "chipload = feed/(rpm×flutes): 1800/(18000×2)=0.05")
expect(approxEqual(cl!, 0.05), "computed value is 0.05 mm/tooth")
let cl4 = ChipLoadPreflight.chipLoad(feedRateMmPerMin: 1200, rpm: 20000, flutes: 4)
expect(cl4 != nil && approxEqual(cl4!, 1200.0 / (20000.0 * 4)), "4-flute math: 1200/(20000×4)=0.015")
expect(ChipLoadPreflight.chipLoad(feedRateMmPerMin: 1000, rpm: 0, flutes: 2) == nil,
       "rpm=0 → nil (no div-by-zero verdict)")

// --- AC2: in-range → .ok at BOTH edges --------------------------------------
// softwood window 0.04–0.06 @18k×2f ⇒ feed edges 1440 / 2160.
let lowEdge = ChipLoadPreflight.evaluate(material: "pine", bitDiameterMm: 6.0,
                                         feedRateMmPerMin: 1440, rpm: 18000, flutes: 2, seed: seed)
expect(lowEdge == .ok, "low edge 1440mm/min ⇒ 0.040 exactly → .ok (got \(lowEdge))")
let highEdge = ChipLoadPreflight.evaluate(material: "pine", bitDiameterMm: 6.0,
                                          feedRateMmPerMin: 2160, rpm: 18000, flutes: 2, seed: seed)
expect(highEdge == .ok, "high edge 2160mm/min ⇒ 0.060 exactly → .ok (got \(highEdge))")
let midOk = ChipLoadPreflight.evaluate(material: "softwood", bitDiameterMm: 3.175,
                                       feedRateMmPerMin: 1800, rpm: 18000, flutes: 2, seed: seed)
expect(midOk == .ok, "mid-range 0.05 → .ok")

// --- AC3: out-of-range → .warning naming computed vs recommended ------------
let verdict = ChipLoadPreflight.evaluate(material: "softwood", bitDiameterMm: 6.0,
                                         feedRateMmPerMin: 3000, rpm: 18000, flutes: 2, seed: seed)
guard case .warning(let computed, let recommendedText) = verdict else {
    print("ShopPilotVerify2023a: FAIL — expected .warning for 3000mm/min, got \(verdict)")
    exit(1)
}
expect(approxEqual(computed, 3000.0 / 36000.0), "warning carries computed 0.083 mm/tooth")
expect(recommendedText.contains("0.040") && recommendedText.contains("0.060"),
       "recommended text names 0.040–0.060 window (got \"\(recommendedText)\")")
let tooLow = ChipLoadPreflight.evaluate(material: "hardwood", bitDiameterMm: 6.0,
                                        feedRateMmPerMin: 900, rpm: 18000, flutes: 2, seed: seed)
if case .warning = tooLow {} else {
    print("ShopPilotVerify2023a: FAIL — expected .warning below hardwood window, got \(tooLow)")
    exit(1)
}
// Unknown material / unresolvable inputs stay silent (.noData).
if case .noData = ChipLoadPreflight.evaluate(material: "titanium", bitDiameterMm: 6.0,
                                             feedRateMmPerMin: 1000, rpm: 18000, flutes: 2, seed: seed) {} else {
    print("ShopPilotVerify2023a: FAIL — unknown material should be .noData")
    exit(1)
}

// --- AC5/AC6: tree integration + preset-trusted skip + severity -------------
let mill = Tool(
    id: UUID(), name: "6mm upcut", type: .endMill,
    diameter: 6.35, cuttingLength: 20, totalLength: 40,
    shankDiameter: 6, flutes: 2, cutData: []
)

// Out-of-range feeds on a normal op → CHIP-LOAD warning appears.
let warnTree = ToolpathTreeManager()
let hotNode = warnTree.addOperation("Profile Hot")
var hotParams = ProfileToolpathParams()
hotParams.feedRateMmPerMin = 3600
hotParams.spindleRpm = 18000
hotParams.maxDepthOfCutMm = 2.0
hotNode.paramsJSON = String(data: try! JSONEncoder().encode(hotParams), encoding: .utf8)
hotNode.assignTool(mill.id)

let issues = ToolpathPreflight.checkTree(
    warnTree, vectors: [], materialThicknessMm: 12.0,
    tools: [mill], materialName: "pine"
)
let chipIssues = issues.filter { $0.ruleID == "CHIP-LOAD" }
expect(chipIssues.count == 1, "out-of-range op yields exactly one CHIP-LOAD issue (got \(issues.count) total)")
expect(chipIssues[0].severity == .warning, "CHIP-LOAD severity is warning-tier")
if case .warnOnly = chipIssues[0].fix {} else {
    print("ShopPilotVerify2023a: FAIL — CHIP-LOAD fix must be .warnOnly, got \(chipIssues[0].fix)")
    exit(1)
}
expect(chipIssues[0].message.contains("0.100"), "issue message names computed chip load (got: \(chipIssues[0].message))")
expect(chipIssues[0].message.contains("0.040"), "issue message names recommended range")
expect(!issues.contains { $0.severity == .error },
       "chip-load problem alone NEVER produces an error-severity (export-blocking) issue")

// In-range op → no CHIP-LOAD issue.
var okTree = ToolpathTreeManager()
let calmNode = okTree.addOperation("Profile Calm")
var calmParams = ProfileToolpathParams()
calmParams.feedRateMmPerMin = 1800
calmParams.spindleRpm = 18000
calmNode.paramsJSON = String(data: try! JSONEncoder().encode(calmParams), encoding: .utf8)
calmNode.assignTool(mill.id)
let calmIssues = ToolpathPreflight.checkTree(
    okTree, vectors: [], materialThicknessMm: 12.0,
    tools: [mill], materialName: "pine"
).filter { $0.ruleID == "CHIP-LOAD" }
expect(calmIssues.isEmpty, "in-range feeds produce no CHIP-LOAD warning")

// Preset-trusted op (H-501 lineage) → warning skipped despite bad feeds.
var presetTree = ToolpathTreeManager()
let trustedNode = presetTree.addOperation("Profile Preset")
trustedNode.paramsJSON = String(data: try! JSONEncoder().encode(hotParams), encoding: .utf8)
trustedNode.assignTool(mill.id)
trustedNode.feedsFromPreset = true   // filled via MaterialBitPresetPicker (SPK-1920e lineage)
let presetIssues = ToolpathPreflight.checkTree(
    presetTree, vectors: [], materialThicknessMm: 12.0,
    tools: [mill], materialName: "pine"
).filter { $0.ruleID == "CHIP-LOAD" }
expect(presetIssues.isEmpty, "preset-trusted op skips the chip-load warning even when out of range")

// Same op without the trust flag still warns (control).
trustedNode.feedsFromPreset = false
let untrustedIssues = ToolpathPreflight.checkTree(
    presetTree, vectors: [], materialThicknessMm: 12.0,
    tools: [mill], materialName: "pine"
).filter { $0.ruleID == "CHIP-LOAD" }
expect(untrustedIssues.count == 1, "same op without preset trust warns again")

print("ShopPilotVerify2023a: PASS")

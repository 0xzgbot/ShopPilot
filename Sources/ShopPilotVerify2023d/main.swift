import Foundation
import ShopPilotCore
import ShopPilotGeometry

// SPK-2023d — rest fields on the Pocket form (UI card).
//
// The form itself lives in the app target (Sources/ShopPilot/ContentView.swift,
// `PocketParamsForm` — audit note: it was NEVER in SpecialtyParamsForms.swift),
// and a CLT cannot import the app target. This gate is therefore two layers:
//
//   BEHAVIORAL (real execution through ShopPilotCore):
//     B1 params with previousToolDiameterMm set survive a round-trip through
//        the SAME JSONEncoder/JSONDecoder contract the UI persists
//        (applyPocketParams stores node.paramsJSON = encoded params; recalc
//        decodes them back into PocketToolpathParams).
//     B2 legacy JSON without the key decodes previousToolDiameterMm = 0
//        (full clear) — persisted documents from before SPK-2023c load.
//     B3 prev=0 vs prev>0 outputs DIFFER: with a 1.5875 mm current tool and
//        6.35 mm previous tool, every cut endpoint stays inside the leftover
//        band (engine contract proven fully by ShopPilotVerify2023c; here we
//        re-prove the divergence the new UI field actually toggles).
//
//   COMPILE-LEVEL (source-contract greps over the app target; the strings are
//   type-checked by `swift_locked.sh build --target ShopPilot`, their wiring
//   semantics asserted textually here — the standard pattern, cf. Verify2024b):
//     C1 PocketParamsForm embeds the "Previous tool" picker bound to `tools`
//        and the numeric "Previous tool Ø (mm)" row bound to
//        $params.previousToolDiameterMm.
//     C2 picker selection fills the picked tool's diameter; None resets to 0.
//     C3 the field flows through the SAME recalc path as every other param
//        edit: onApply(params) → session.applyPocketParams(newParams, to:),
//        which recomputes the engine and updates the node.
//     C4 V-carve flat-clearance audit: VCarveParams exposes NO
//        previousToolDiameterMm (no engine support), so NO rest field is
//        added to VCarveParamsForm — asserted against Core source.

func expect(_ cond: Bool, _ msg: String) {
    guard cond else { print("ShopPilotVerify2023d: FAIL — \(msg)"); exit(1) }
}

func approxEqual(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool {
    abs(a - b) <= tol
}

// --- B1/B2: persist contract through the same JSON coding the UI uses -------
var params = PocketToolpathParams(
    clearanceMode: .zigzag,
    stepOverMm: 3.0,
    feedRateMmPerMin: 1000,
    plungeFeedRateMmPerMin: 300,
    maxDepthOfCutMm: 2.0,
    toolDiameterMm: 1.5875,
    safetyHeightMm: 5.0,
    spindleRpm: 18000,
    previousToolDiameterMm: 6.35
)
do {
    // B1 — round-trip with the rest value set (what Apply → paramsJSON does).
    let data = try JSONEncoder().encode(params)
    let back = try JSONDecoder().decode(PocketToolpathParams.self, from: data)
    expect(approxEqual(back.previousToolDiameterMm, 6.35),
           "previousToolDiameterMm=6.35 lost in the UI persist round-trip")
    expect(approxEqual(back.toolDiameterMm, 1.5875),
           "current tool diameter lost in the round-trip")
} catch {
    print("ShopPilotVerify2023d: FAIL — encode/decode threw \(error)")
    exit(1)
}

// B2 — legacy document JSON (pre-2023c, no key) decodes to 0 = full clear.
let legacyJSON = #"{"clearanceMode":"zigzag","stepOverMm":3,"feedRateMmPerMin":1000,"plungeFeedRateMmPerMin":300,"maxDepthOfCutMm":2,"toolDiameterMm":6.35,"safetyHeightMm":5,"spindleRpm":18000,"startDepthMm":0,"passCount":0,"exactStepDepth":false,"cutDirection":"climb","rasterAngleDegrees":0,"profilePass":"last","allowanceMm":0,"rampPlungeMoves":false,"useVectorSelectionOrder":false}"#
do {
    let legacy = try JSONDecoder().decode(PocketToolpathParams.self, from: Data(legacyJSON.utf8))
    expect(legacy.previousToolDiameterMm == 0,
           "legacy decode must default previousToolDiameterMm to 0")
} catch {
    print("ShopPilotVerify2023d: FAIL — legacy decode threw \(error)")
    exit(1)
}
print("ok B1/B2 persist round-trip + legacy decode default 0")

// --- B3: prev=0 vs prev>0 outputs differ ------------------------------------
let points: [VectorPoint] = [
    VectorPoint(x: 0, y: 0),
    VectorPoint(x: 60, y: 0),
    VectorPoint(x: 60, y: 40),
    VectorPoint(x: 0, y: 40),
    VectorPoint(x: 0, y: 0)
]
let rect = VectorPath(name: "Rect", points: points, isClosed: true)

func cutEndpoints(_ lines: [String]) -> [(Double, Double)] {
    lines.filter { $0.hasPrefix("G1 X") }.compactMap { line in
        let toks = line.split(separator: " ")
        guard let x = toks.first(where: { $0.hasPrefix("X") }).flatMap({ Double($0.dropFirst()) }),
              let y = toks.first(where: { $0.hasPrefix("Y") }).flatMap({ Double($0.dropFirst()) })
        else { return nil }
        return (x, y)
    }
}

let fullClear = PocketToolpathEngine.compute(vectors: [rect], params: params, stockHeightMm: 4.0)
params.previousToolDiameterMm = 0
let zeroClear = PocketToolpathEngine.compute(vectors: [rect], params: params, stockHeightMm: 4.0)
expect(fullClear.gcodeLines != zeroClear.gcodeLines,
       "prev>0 output identical to prev=0 — the UI field would be a no-op")

// The rest pass only cuts the leftover band: nothing strictly inside the
// region the 6.35 mm tool already cleared (inset by its radius).
let cMinX = 6.35 / 2, cMaxX = 60 - 6.35 / 2
let cMinY = 6.35 / 2, cMaxY = 40 - 6.35 / 2
for (x, y) in cutEndpoints(fullClear.gcodeLines) {
    let insideCleared = x > cMinX && x < cMaxX && y > cMinY && y < cMaxY
    expect(!insideCleared,
           "rest cut (\(x), \(y)) lies inside the previously-cleared region")
}
print("ok B3 prev=0 vs prev>0 differ; all \(cutEndpoints(fullClear.gcodeLines).count) rest endpoints in leftover band")

// --- Source contracts (compile-level; see header) ----------------------------
func fileText(_ rel: String) -> String {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(rel)
    guard let s = try? String(contentsOf: url, encoding: .utf8) else {
        print("ShopPilotVerify2023d: FAIL — cannot read \(rel) from repo root")
        exit(1)
    }
    return s
}

/// Brace-counted body of `struct <Name>` so nested types can't fool the scan.
func structBody(of name: String, in text: String) -> String? {
    guard let header = text.range(of: "struct \(name)") else { return nil }
    guard let open = text.range(of: "{", range: header.upperBound..<text.endIndex) else { return nil }
    var depth = 0
    var i = open.lowerBound
    while i < text.endIndex {
        let ch = text[i]
        if ch == "{" { depth += 1 }
        if ch == "}" {
            depth -= 1
            if depth == 0 { return String(text[open.lowerBound...i]) }
        }
        i = text.index(after: i)
    }
    return nil
}

let ui = fileText("Sources/ShopPilot/ContentView.swift")
guard let form = structBody(of: "PocketParamsForm", in: ui) else {
    print("ShopPilotVerify2023d: FAIL — PocketParamsForm body not found")
    exit(1)
}

// C1 — field + picker present, bound to the right targets.
expect(form.contains(#"Picker("Previous tool""#),
       "PocketParamsForm: no Previous-tool picker")
expect(form.contains("$params.previousToolDiameterMm"),
       "PocketParamsForm: numeric row not bound to previousToolDiameterMm")
expect(form.contains(#"numRow("Previous tool Ø (mm)""#),
       "PocketParamsForm: no editable numeric Ø row")
expect(form.contains("ForEach(tools)"),
       "PocketParamsForm: picker does not enumerate session tools")

// C2 — selection fills diameter; None resets to 0 (manual entry stays legal).
expect(form.contains("previousToolSelection"),
       "PocketParamsForm: picker selection binding missing")
expect(form.contains("params.previousToolDiameterMm = tool.diameter"),
       "picker must fill the selected tool's diameter")
expect(form.contains("params.previousToolDiameterMm = 0"),
       "picker None/default must reset to 0 (full clear)")

// C3 — same recalc flow as every other param edit on this form:
// Apply button → onApply → session.applyPocketParams (engine recompute).
expect(ui.contains(#"session.applyPocketParams(newParams, to: node.id)"#),
       "call site must route Apply through applyPocketParams (markDirty + regenerate)")

// C4 — V-carve audit: no engine support ⇒ no invented UI field.
let vcarveEngine = fileText("Sources/ShopPilotCore/VCarveEngine.swift")
expect(!vcarveEngine.contains("previousToolDiameterMm"),
       "VCarveEngine gained previousTool support — re-audit VCarveParamsForm")
if let vcarveForm = structBody(of: "VCarveParamsForm", in: ui) {
    expect(!vcarveForm.contains("previousToolDiameterMm"),
           "VCarveParamsForm must not expose an unsupported rest field")
}
print("ok C1-C4 source contracts hold")

print("ShopPilotVerify2023d: PASS — rest fields on the Pocket form verified (persist + divergence behaviorally, UI wiring at compile/source-contract level)")

import Foundation
import ShopPilotCore

// SPK-2024b verify — named material+bit presets over parameters.
//
// AC1: catalog ships "Walnut 18 mm + 90° V-bit" with positive depth/feed/rpm.
// AC2: one pick fills Cut depth / feed / plunge / rpm on Profile, Pocket AND
//      V-Carve params via the shared PresetFillable conformance.
// AC3: preset-filled params stay Codable round-trip-safe (persist contract).
// AC4: a node filled from the named preset sets feedsFromPreset so the
//      chip-load preflight warning stays silent (SPK-2023a AC5 contract).
// AC5: source contract — MaterialBitPresetPicker is embedded in all three
//      Cut 2D forms and every field stays visible (RPM rows present).

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerify2024b: FAIL — \(msg)")
        exit(1)
    }
}

func approxEqual(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool {
    abs(a - b) <= tol
}

// --- AC1: the named combo exists with machine-ready values ------------------
let walnut = MaterialBitPresetCatalog.named("Walnut 18 mm + 90° V-bit")
expect(walnut != nil, "catalog ships the exact named combo")
let p = walnut!
expect(p.cutDepthMm > 0 && p.feedRateMmPerMin > 0,
       "depth and feed are positive")
expect(p.plungeFeedRateMmPerMin > 0 && p.spindleRpm > 0,
       "plunge and rpm are positive")
expect(MaterialBitPresetCatalog.shipped.first(where: { $0.id == p.id }) != nil,
       "preset resolvable by id too")
expect(Set(MaterialBitPresetCatalog.shipped.map(\.name)).count
       == MaterialBitPresetCatalog.shipped.count,
       "preset names are unique (picker keys selections on name)")
expect(MaterialBitPresetCatalog.named("No Such Combo") == nil,
       "unknown names do not resolve")

// --- AC2: shared fill across all three Cut 2D strategies --------------------
var profile = ProfileToolpathParams()
profile.feedRateMmPerMin = 999
profile.spindleRpm = 0
var pocket = PocketToolpathParams()
pocket.maxDepthOfCutMm = 42
var vcarve = VCarveParams()
vcarve.feedRateMmPerMin = 777

// Non-depth geometry fields are untouched by the fill (progressive scope).
var profile2 = profile
profile2.applyPreset(p)
expect(approxEqual(profile2.maxDepthOfCutMm, p.cutDepthMm), "Profile: depth filled")
expect(approxEqual(profile2.feedRateMmPerMin, p.feedRateMmPerMin), "Profile: feed filled")
expect(approxEqual(profile2.plungeFeedRateMmPerMin, p.plungeFeedRateMmPerMin), "Profile: plunge filled")
expect(approxEqual(profile2.spindleRpm, p.spindleRpm), "Profile: rpm filled")

var pocket2 = pocket
pocket2.applyPreset(p)
expect(approxEqual(pocket2.maxDepthOfCutMm, p.cutDepthMm), "Pocket: depth filled")
expect(approxEqual(pocket2.feedRateMmPerMin, p.feedRateMmPerMin), "Pocket: feed filled")
expect(approxEqual(pocket2.spindleRpm, p.spindleRpm), "Pocket: rpm filled")

var vcarve2 = vcarve
vcarve2.applyPreset(p)
expect(approxEqual(vcarve2.maxDepthOfCutMm, p.cutDepthMm), "V-Carve: cut depth filled")
expect(approxEqual(vcarve2.feedRateMmPerMin, p.feedRateMmPerMin), "V-Carve: feed filled")
expect(approxEqual(vcarve2.spindleRpm, p.spindleRpm), "V-Carve: rpm filled")

expect(approxEqual(profile2.toolDiameterMm, profile.toolDiameterMm),
       "Profile: tool diameter untouched by preset fill")
expect(profile2.finishPasses == profile.finishPasses,
       "Profile: finish passes untouched")

// --- AC3: preset-filled params round-trip -----------------------------------
do {
    let enc = JSONEncoder()
    let dec = JSONDecoder()
    let pj = try dec.decode(ProfileToolpathParams.self, from: try enc.encode(profile2))
    expect(approxEqual(pj.feedRateMmPerMin, profile2.feedRateMmPerMin)
           && approxEqual(pj.spindleRpm, profile2.spindleRpm)
           && approxEqual(pj.maxDepthOfCutMm, profile2.maxDepthOfCutMm),
           "Profile: filled params JSON round-trip")
    let kj = try dec.decode(PocketToolpathParams.self, from: try enc.encode(pocket2))
    expect(approxEqual(kj.feedRateMmPerMin, pocket2.feedRateMmPerMin)
           && approxEqual(kj.spindleRpm, pocket2.spindleRpm)
           && approxEqual(kj.maxDepthOfCutMm, pocket2.maxDepthOfCutMm),
           "Pocket: filled params JSON round-trip")
    let vj = try dec.decode(VCarveParams.self, from: try enc.encode(vcarve2))
    expect(approxEqual(vj.feedRateMmPerMin, vcarve2.feedRateMmPerMin)
           && approxEqual(vj.spindleRpm, vcarve2.spindleRpm)
           && approxEqual(vj.maxDepthOfCutMm, vcarve2.maxDepthOfCutMm),
           "V-Carve: filled params JSON round-trip")
} catch {
    print("ShopPilotVerify2024b: FAIL — round-trip threw \(error)")
    exit(1)
}

// The preset struct itself is Codable (future persist surface).
do {
    let data = try JSONEncoder().encode(p)
    let back = try JSONDecoder().decode(NamedMaterialBitPreset.self, from: data)
    expect(back == p, "NamedMaterialBitPreset Codable round-trip")
} catch {
    print("ShopPilotVerify2024b: FAIL — preset Codable threw \(error)")
    exit(1)
}

// --- AC4: preset-filled node is chip-load trusted ----------------------------
let mill = Tool(
    id: UUID(), name: "6mm upcut", type: .endMill,
    diameter: 6.35, cuttingLength: 20, totalLength: 40,
    shankDiameter: 6, flutes: 2, cutData: []
)

func chipIssuesFor(feedsFromPreset flag: Bool) -> [ToolpathPreflightIssue] {
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Profile Preset Filled Op")
    var params = ProfileToolpathParams()
    params.applyPreset(p)
    params.feedRateMmPerMin = 3600   // deliberately out-of-range chip load
    node.paramsJSON = String(data: try! JSONEncoder().encode(params), encoding: .utf8)
    node.assignTool(mill.id)
    node.feedsFromPreset = flag
    return ToolpathPreflight.checkTree(
        tree, vectors: [], materialThicknessMm: 12.0,
        tools: [mill], materialName: "pine"   // softwood band covers the 6.35mm bit
    ).filter { $0.ruleID == "CHIP-LOAD" }
}

expect(chipIssuesFor(feedsFromPreset: false).count == 1,
       "same feeds without preset trust still warn (control)")
expect(chipIssuesFor(feedsFromPreset: true).isEmpty,
       "named-preset-trusted op stays silent despite out-of-range feed")

// --- AC5: source contract — picker embedded in all three forms ---------------
// A CLT cannot import the app target; assert the wiring textually from the
// repo root (verify_locked runs there).
func fileText(_ rel: String) -> String {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(rel)
    guard let s = try? String(contentsOf: url, encoding: .utf8) else {
        print("ShopPilotVerify2024b: FAIL — cannot read \(rel) from repo root")
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
for form in ["ProfileParamsForm", "PocketParamsForm", "VCarveParamsForm"] {
    guard let body = structBody(of: form, in: ui) else {
        print("ShopPilotVerify2024b: FAIL — \(form) body not found")
        exit(1)
    }
    expect(body.contains("MaterialBitPresetPicker("),
           "\(form): preset picker embedded above the field groups")
    expect(body.contains("Spindle (RPM, 0 = off)"),
           "\(form): rpm row visible so the filled value is editable")
}
let pickerFile = fileText("Sources/ShopPilot/SpecialtyParamsForms.swift")
guard let pickerBody = structBody(of: "MaterialBitPresetPicker", in: pickerFile) else {
    print("ShopPilotVerify2024b: FAIL — MaterialBitPresetPicker body not found")
    exit(1)
}
expect(pickerBody.contains("MaterialBitPresetCatalog.named(chosen)"),
       "picker resolves named combos on selection")
expect(pickerBody.contains("node.feedsFromPreset = true"),
       "picker marks the node preset-trusted")
expect(ui.contains("tools: session.toolDatabase.tools"),
       "forms receive the tool database")

print("ShopPilotVerify2024b: PASS — named presets fill depth/feed/rpm on all Cut 2D forms, chip-load silent when preset-trusted")

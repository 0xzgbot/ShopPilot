import Foundation
import ShopPilotCore
import ShopPilotGeometry

// One-shot generator for SPK-SHAKEb fixture packages.
// Builds real Job model instances (via the recipe + engine, not hand-rolled
// JSON), saves them with DocumentSaver, then re-loads with DocumentLoader to
// prove the packages are openable. Output lands in fixtures/shoppilot/.

func fail(_ msg: String) -> Never {
    fputs("FIXTURE-GEN FAIL: \(msg)\n", stderr)
    exit(1)
}

func encodeJSON<T: Encodable>(_ value: T) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

// ── 1. Calibration package ────────────────────────────────────────────────
func makeCalibrationPackage() -> ShopPilotPackagePayload {
    // 50×50 mm closed square at (25,25) on 200×200×18 stock.
    let layerID = UUID()
    let square = VectorPath(
        id: UUID(),
        name: "Calibration Square",
        points: [
            VectorPoint(x: 25, y: 25),
            VectorPoint(x: 75, y: 25),
            VectorPoint(x: 75, y: 75),
            VectorPoint(x: 25, y: 75),
            VectorPoint(x: 25, y: 25), // close the loop
        ],
        isClosed: true,
        layerId: layerID
    )
    let layer = Layer(id: layerID, name: "Cut", vectors: [square])
    let sheet = Sheet(
        name: "Calibration Sheet",
        width: 200, depth: 200, height: 18,
        layers: [layer]
    )
    let job = Job(name: "Calibration", sheets: [sheet])

    // Real Profile toolpath on the square (1/4" end mill defaults).
    let params = ProfileToolpathParams()
    let result = ProfileToolpathEngine.compute(
        vectors: [square],
        params: params,
        material: nil,
        stockHeightMm: 18.0
    )
    let op = PersistedToolpath(
        name: "Profile 1",
        toolpathResult: result.gcodeLines.joined(separator: "\n"),
        estimatedTimeSeconds: result.estimatedTimeSeconds,
        isDirty: false,
        paramsJSON: encodeJSON(params)
    )
    return ShopPilotPackagePayload(job: job, toolpaths: [op])
}

// ── 2. Sign package (real recipe) ─────────────────────────────────────────
func makeSignPackage() -> ShopPilotPackagePayload {
    let job = SignRecipeManager.createSignJob(
        jobName: "Sign SHOP",
        text: "SHOP",
        fontSize: 48,
        vBitAngle: 90,
        vCarveDepth: 0.5,
        feedRate: 1200
    )
    var toolpaths: [PersistedToolpath] = []
    if let gcode = job.vcarveGCode, !gcode.isEmpty {
        toolpaths.append(PersistedToolpath(
            name: "V-Carve 1 (Recipe)",
            toolpathResult: gcode.joined(separator: "\n"),
            estimatedTimeSeconds: job.vcarveTimeSeconds,
            isDirty: false,
            paramsJSON: job.vcarveParamsJSON
        ))
    }
    return ShopPilotPackagePayload(job: job, toolpaths: toolpaths)
}

// ── main ──────────────────────────────────────────────────────────────────
let fixturesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("fixtures")
    .appendingPathComponent("shoppilot")

let saver = DocumentSaver()
let loader = DocumentLoader()

let calibration = makeCalibrationPackage()
let calibrationURL = fixturesRoot.appendingPathComponent("Calibration.shoppilot")
try? FileManager.default.removeItem(at: calibrationURL)
try saver.save(calibration, to: calibrationURL)
let loadedCal = try loader.loadPayload(from: calibrationURL)
guard loadedCal.job.name == "Calibration" else { fail("calibration name round-trip") }
guard let calSheet = loadedCal.job.sheets.first, calSheet.layers.count == 1 else {
    fail("calibration sheet/layers round-trip")
}
guard loadedCal.toolpaths.count == 1, loadedCal.toolpaths[0].name == "Profile 1" else {
    fail("calibration toolpath round-trip")
}
print("Calibration.shoppilot OK — \(calSheet.width)x\(calSheet.depth)x\(calSheet.height), " +
      "layers=\(calSheet.layers.count), vectors=\(calSheet.layers[0].vectors.count), " +
      "toolpaths=\(loadedCal.toolpaths.count)")

let sign = makeSignPackage()
let signURL = fixturesRoot.appendingPathComponent("Sign.shoppilot")
try? FileManager.default.removeItem(at: signURL)
try saver.save(sign, to: signURL)
let loadedSign = try loader.loadPayload(from: signURL)
guard loadedSign.job.name == "Sign SHOP" else { fail("sign name round-trip") }
guard let signSheet = loadedSign.job.sheets.first else { fail("sign sheet round-trip") }
let textLayer = signSheet.layers.first { $0.name == "Text" }
let borderLayer = signSheet.layers.first { $0.name == "Border" }
guard let textLayer, let borderLayer else { fail("sign layers round-trip") }
guard textLayer.vectors.count == 4, borderLayer.vectors.count == 1 else {
    fail("sign vector counts round-trip (text=\(textLayer.vectors.count), border=\(borderLayer.vectors.count))")
}
guard loadedSign.toolpaths.count == 1, loadedSign.toolpaths[0].name == "V-Carve 1 (Recipe)" else {
    fail("sign toolpath round-trip")
}
print("Sign.shoppilot OK — text=\(textLayer.vectors.count) glyphs, border=\(borderLayer.vectors.count), " +
      "vcarve lines=\((loadedSign.toolpaths[0].toolpathResult ?? "").components(separatedBy: .newlines).count)")

print("FIXTURE-GEN DONE")

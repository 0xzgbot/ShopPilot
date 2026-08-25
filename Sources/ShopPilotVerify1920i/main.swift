import Foundation
import ShopPilotCore

// SPK-1920i — contract goldens (docs-type card).
//
// Builds three jobs programmatically via SampleProjectsStore / model types,
// saves each as a `.shoppilot` fixture under fixtures/parity/, reopens every
// fixture with DocumentLoader and asserts vectors / toolpaths / relief /
// inlay pocket+plug params survive the round trip byte-for-byte where the
// format guarantees it:
//
//   1. sign_golden.shoppilot   — the Sign sample (vectors only)
//   2. plaque_golden.shoppilot — 3D plaque: vectors + ACTIVE relief +
//                                relief component + Rough3D/Finish3D ops
//   3. inlay_golden.shoppilot  — inlay job: vector motif + pocket/plug ops
//
// The engine glue lives in ShopPilotCore (DocumentSaver/DocumentLoader);
// AppSession UI wiring is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func jsonOf<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8) ?? ""
}

func decodeJSON<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    guard let data = json.data(using: .utf8) else {
        throw VerifyError.failed("paramsJSON is not UTF-8")
    }
    return try JSONDecoder().decode(type, from: data)
}

let fileManager = FileManager.default
let repoRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let parityDir = repoRoot.appendingPathComponent("fixtures/parity", isDirectory: true)

func fixtureURL(_ stem: String) -> URL {
    parityDir.appendingPathComponent(stem).appendingPathExtension("shoppilot")
}

/// Deterministic dome grid for the plaque's relief component.
func domeHeightfield() -> HeightfieldData {
    let gw = 12
    let gh = 9
    let cell = 2.0
    var heights = [Double](repeating: 0, count: gw * gh)
    for y in 0..<gh {
        for x in 0..<gw {
            let dx = (Double(x) + 0.5 - Double(gw) / 2) / (Double(gw) / 2)
            let dy = (Double(y) + 0.5 - Double(gh) / 2) / (Double(gh) / 2)
            let r2 = dx * dx + dy * dy
            heights[y * gw + x] = max(0, 1 - r2) * 6.5
        }
    }
    return HeightfieldData(width: gw, height: gh, cellSizeMm: cell, minX: 40, minY: 30, heights: heights)
}

func main() throws {
    try fileManager.createDirectory(at: parityDir, withIntermediateDirectories: true)

    // ---------------------------------------------------------------
    // 1. Sign sample — save as-is (vectors only), reopen, compare.
    // ---------------------------------------------------------------
    let signSample = SampleProjectsStore.samples[0]
    guard let signPayload = SampleProjectsStore.payload(for: signSample.id) else {
        throw VerifyError.failed("SampleProjectsStore has no payload for the Sign sample")
    }
    let signURL = fixtureURL("sign_golden")
    try DocumentSaver().save(signPayload, to: signURL)

    let signBack = try DocumentLoader().loadPayload(from: signURL)
    let signJob = signBack.job
    try expect(signJob.name == "Sign — V-Carve Greeting", "sign job name survived")
    try expect(signJob.id == signPayload.job.id, "sign job id survived")
    try expect(signJob.sheets.count == 1, "sign sheet count")
    let signSheet = try expectNotNil(signJob.sheets.first, "sign sheet present")
    try expect(signSheet.width == 450 && signSheet.depth == 300 && signSheet.height == 18,
               "sign stock dims survived (\(signSheet.width)x\(signSheet.depth)x\(signSheet.height))")
    let origVectors = signPayload.job.sheets.flatMap(\.layers).flatMap(\.vectors)
    let backVectors = signSheet.layers.flatMap(\.vectors)
    try expect(backVectors.count == origVectors.count,
               "sign vector count survived (\(backVectors.count) vs \(origVectors.count))")
    for (a, b) in zip(origVectors, backVectors) {
        try expect(b.name == a.name, "vector name \(a.name)")
        try expect(b.isClosed == a.isClosed, "vector isClosed \(a.name)")
        try expect(b.points.count == a.points.count, "vector point count \(a.name)")
        try expect(b.points.map { "\($0.x),\($0.y)" } == a.points.map { "\($0.x),\($0.y)" },
                   "vector points \(a.name)")
    }

    // ---------------------------------------------------------------
    // 2. 3D plaque — vectors + ACTIVE relief + component + 3D toolpaths.
    // ---------------------------------------------------------------
    let plaqueIndex = SampleProjectsStore.samples.firstIndex(where: { $0.category == "Plaque" }) ?? 3
    guard var plaquePayload = SampleProjectsStore.payload(for: plaqueIndex) else {
        throw VerifyError.failed("SampleProjectsStore has no payload for the Plaque sample")
    }
    let activeRelief = plaquePayload.job.stlHeightfield
    try expect(activeRelief != nil, "plaque sample ships an ACTIVE relief")
    // Exercise the component stack too (SPK-0700 model).
    let component = ReliefComponent(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        name: "Cameo Dome",
        heightfield: domeHeightfield(),
        combineMode: .combineAdd,
        visible: true,
        heightScale: 1.25
    )
    plaquePayload.job.reliefComponents = [component]

    let roughParams = HeightfieldRoughParams(
        toolDiameterMm: 6.35, stepDownMm: 1.8, stepOverMm: 1.2,
        feedRateMmPerMin: 900, plungeFeedRateMmPerMin: 250,
        safeZHeightMm: 4.0, stockAllowanceMm: 0.4, spindleRpm: 18000,
        previousToolDiameterMm: 0, inverseMill: false
    )
    let finishParams = HeightfieldFinishParams(
        toolDiameterMm: 1.5, stepOverMm: 0.35,
        feedRateMmPerMin: 1200, plungeFeedRateMmPerMin: 220,
        safeZHeightMm: 4.0, spindleRpm: 21000
    )
    let roughGCode = "; golden rough pass (hand-written contract text)\nG0 Z4.000\nG0 X10.000 Y10.000\nG1 Z-1.800 F250\nG1 X290.000 F900\n"
    let finishGCode = "; golden finish pass (hand-written contract text)\nG0 Z4.000\nG1 Z-0.350 F220\nG1 X10.000 Y190.000 F1200\n"
    plaquePayload.toolpaths = [
        PersistedToolpath(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Rough 3D — Plaque",
            toolpathResult: roughGCode,
            estimatedTimeSeconds: 640.5,
            paramsJSON: try jsonOf(roughParams)
        ),
        PersistedToolpath(
            id: UUID(uuidString: "66666666-7777-8888-9999-A00000000000")!,
            name: "Finish 3D — Plaque",
            toolpathResult: finishGCode,
            estimatedTimeSeconds: 1815.25,
            paramsJSON: try jsonOf(finishParams)
        ),
    ]
    let plaqueURL = fixtureURL("plaque_golden")
    try DocumentSaver().save(plaquePayload, to: plaqueURL)

    let plaqueBack = try DocumentLoader().loadPayload(from: plaqueURL)
    let plaqueJob = plaqueBack.job
    try expect(plaqueJob.name == "Plaque — Text Relief", "plaque job name survived")

    // Vectors survive.
    let plaqueOrigVectors = plaquePayload.job.sheets.flatMap(\.layers).flatMap(\.vectors)
    let plaqueBackVectors = plaqueJob.sheets.flatMap(\.layers).flatMap(\.vectors)
    try expect(plaqueBackVectors.count == plaqueOrigVectors.count,
               "plaque vector count (\(plaqueBackVectors.count) vs \(plaqueOrigVectors.count))")
    try expect(plaqueBackVectors.map(\.name) == plaqueOrigVectors.map(\.name), "plaque vector names/order")

    // Relief round-trip: ACTIVE heightfield verbatim.
    let backRelief = try expectNotNil(plaqueJob.stlHeightfield, "ACTIVE relief reopened")
    let origRelief = try expectNotNil(activeRelief, "ACTIVE relief original")
    try expect(backRelief.width == origRelief.width && backRelief.height == origRelief.height,
               "relief grid dims (\(backRelief.width)x\(backRelief.height))")
    try expect(backRelief.cellSizeMm == origRelief.cellSizeMm, "relief cell size")
    try expect(backRelief.minX == origRelief.minX && backRelief.minY == origRelief.minY, "relief origin")
    try expect(backRelief.heights == origRelief.heights, "relief heights array verbatim")

    // Component stack survives (incl. dynamic props).
    let backComponents = plaqueJob.reliefComponents ?? []
    try expect(backComponents.count == 1, "one relief component reopened (\(backComponents.count))")
    let backComponent = try expectNotNil(backComponents.first, "component present")
    try expect(backComponent.id == component.id, "component id")
    try expect(backComponent.name == "Cameo Dome", "component name")
    try expect(backComponent.combineMode == .combineAdd, "component combine mode")
    try expect(backComponent.visible == true, "component visibility")
    try expect(backComponent.heightScale == 1.25, "component heightScale prop")
    try expect(backComponent.heightfield.heights == component.heightfield.heights, "component heights verbatim")

    // 3D toolpaths survive: g-code text + decoded params.
    try expect(plaqueBack.toolpaths.count == 2, "two plaque ops reopened (\(plaqueBack.toolpaths.count))")
    let backRough = try expectNotNil(plaqueBack.toolpaths.first, "rough op present")
    try expect(backRough.name == "Rough 3D — Plaque", "rough op name")
    try expect(backRough.toolpathResult == roughGCode, "rough G-code text verbatim")
    try expect(backRough.estimatedTimeSeconds == 640.5, "rough time estimate")
    let backRoughParams = try decodeJSON(HeightfieldRoughParams.self, try expectNotNil(backRough.paramsJSON, "rough paramsJSON"))
    try expect(backRoughParams.toolDiameterMm == 6.35, "rough tool dia")
    try expect(backRoughParams.stepDownMm == 1.8, "rough stepdown")
    try expect(backRoughParams.feedRateMmPerMin == 900, "rough feed")
    try expect(backRoughParams.stockAllowanceMm == 0.4, "rough stock allowance")
    try expect(backRoughParams.spindleRpm == 18000, "rough rpm")
    let backFinish = plaqueBack.toolpaths[1]
    try expect(backFinish.toolpathResult == finishGCode, "finish G-code text verbatim")
    let backFinishParams = try decodeJSON(HeightfieldFinishParams.self, try expectNotNil(backFinish.paramsJSON, "finish paramsJSON"))
    try expect(backFinishParams.stepOverMm == 0.35, "finish stepover")
    try expect(backFinishParams.spindleRpm == 21000, "finish rpm")

    // ---------------------------------------------------------------
    // 3. Inlay job — pocket + plug params on a small programmatic job.
    // ---------------------------------------------------------------
    let inlayJobID = UUID(uuidString: "19201920-1920-1920-1920-192019201920")!
    let inlaySheetID = UUID(uuidString: "19201920-AAAA-BBBB-CCCC-DDDDEEEEFFFF")!
    let inlayLayerID = UUID(uuidString: "19201920-1111-2222-3333-444455556666")!
    let motifPoints = [
        VectorPoint(x: 20, y: 20), VectorPoint(x: 80, y: 20),
        VectorPoint(x: 80, y: 60), VectorPoint(x: 20, y: 60),
        VectorPoint(x: 20, y: 20),
    ]
    let motif = VectorPath(name: "Inlay Motif", points: motifPoints, isClosed: true, layerId: inlayLayerID)
    let inlayLayer = Layer(id: inlayLayerID, name: "Inlay Layer", vectors: [motif])
    let inlaySheet = Sheet(id: inlaySheetID, name: "Inlay Stock", width: 120, depth: 90, height: 12,
                           layers: [inlayLayer])
    let inlayJob = Job(id: inlayJobID, name: "Inlay — Two Wood", sheets: [inlaySheet])
    let pocketParams = InlayToolpathParams(
        variant: .pocket, inlayDepthMm: 2.4, vBitAngleDegrees: 60,
        safeZHeightMm: 3.0, feedRateMmPerMin: 800, plungeRateMmPerMin: 150,
        toolDiameterMm: 3.175, spindleRpm: 24000
    )
    let plugParams = InlayToolpathParams(
        variant: .plug, inlayDepthMm: 2.4, vBitAngleDegrees: 60,
        safeZHeightMm: 3.0, feedRateMmPerMin: 700, plungeRateMmPerMin: 140,
        toolDiameterMm: 3.175, spindleRpm: 24000
    )
    let inlayPayload = ShopPilotPackagePayload(job: inlayJob, toolpaths: [
        PersistedToolpath(
            id: UUID(uuidString: "A0C6A0C6-1920-1920-1920-000000000001")!,
            name: "Inlay Pocket",
            estimatedTimeSeconds: 96.0,
            paramsJSON: try jsonOf(pocketParams)
        ),
        PersistedToolpath(
            id: UUID(uuidString: "B0A6A0C6-1920-1920-1920-000000000002")!,
            name: "Inlay Plug",
            estimatedTimeSeconds: 84.5,
            paramsJSON: try jsonOf(plugParams)
        ),
    ])
    let inlayURL = fixtureURL("inlay_golden")
    try DocumentSaver().save(inlayPayload, to: inlayURL)

    let inlayBack = try DocumentLoader().loadPayload(from: inlayURL)
    try expect(inlayBack.job.name == "Inlay — Two Wood", "inlay job name survived")
    let inlayMotifBack = inlayBack.job.sheets.first?.layers.first?.vectors.first
    try expect(inlayMotifBack?.points.map { "\($0.x),\($0.y)" } == motifPoints.map { "\($0.x),\($0.y)" },
               "inlay motif points verbatim")
    try expect(inlayMotifBack?.isClosed == true, "inlay motif closed flag")
    try expect(inlayBack.toolpaths.count == 2, "two inlay ops reopened")
    let backPocketNode = inlayBack.toolpaths.first { $0.name == "Inlay Pocket" }
    let backPlugNode = inlayBack.toolpaths.first { $0.name == "Inlay Plug" }
    let backPocket = try decodeJSON(InlayToolpathParams.self,
                                    try expectNotNil(backPocketNode?.paramsJSON, "pocket paramsJSON"))
    let backPlug = try decodeJSON(InlayToolpathParams.self,
                                  try expectNotNil(backPlugNode?.paramsJSON, "plug paramsJSON"))
    try expect(backPocket.variant == .pocket, "pocket variant")
    try expect(backPlug.variant == .plug, "plug variant")
    try expect(backPocket.inlayDepthMm == 2.4 && backPlug.inlayDepthMm == 2.4, "inlay depth 2.4")
    try expect(backPocket.vBitAngleDegrees == 60 && backPlug.vBitAngleDegrees == 60, "V-bit angle 60")
    try expect(backPocket.feedRateMmPerMin == 800, "pocket feed")
    try expect(backPlug.feedRateMmPerMin == 700, "plug feed")
    try expect(backPocket.plungeRateMmPerMin == 150, "pocket plunge")
    try expect(backPlug.spindleRpm == 24000, "plug rpm")

    print("ShopPilotVerify1920i: PASS — 3 fixtures reopened")
}

func expectNotNil<T>(_ value: T?, _ msg: String) throws -> T {
    guard let value = value else { throw VerifyError.failed(msg) }
    return value
}

do {
    try main()
} catch {
    print("ShopPilotVerify1920i: FAIL — \(error)")
    exit(1)
}

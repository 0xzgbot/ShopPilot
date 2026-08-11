import Foundation
import ShopPilotCore
import ShopPilotGeometry

// Test-pack generator: builds a COMPLEX master document with real engines
// (not hand-rolled JSON) so load → modify → save → export round-trips are
// always exercised against the on-disk schema. Output: fixtures/testpack/.

func fail(_ msg: String) -> Never {
    fputs("TESTPACK-GEN FAIL: \(msg)\n", stderr)
    exit(1)
}

func encodeJSON<T: Encodable>(_ value: T) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

// ── Master sheet 1: "Front" — a sign-ish job with 3 layers ───────────────
func makeMasterJob() -> (ShopPilotPackagePayload, String) {
    let stockW = 400.0, stockD = 300.0, stockH = 18.0

    // Layer 1: "Border" — rectangle outline + offset rings.
    let borderID = UUID()
    let border = VectorPath(
        id: UUID(), name: "Outer Border",
        points: [
            VectorPoint(x: 20, y: 20), VectorPoint(x: 380, y: 20),
            VectorPoint(x: 380, y: 280), VectorPoint(x: 20, y: 280),
            VectorPoint(x: 20, y: 20),
        ],
        isClosed: true, layerId: borderID
    )
    let inner = VectorPath(
        id: UUID(), name: "Inner Border",
        points: [
            VectorPoint(x: 40, y: 40), VectorPoint(x: 360, y: 40),
            VectorPoint(x: 360, y: 260), VectorPoint(x: 40, y: 260),
            VectorPoint(x: 40, y: 40),
        ],
        isClosed: true, layerId: borderID
    )
    let borderLayer = Layer(id: borderID, name: "Border", vectors: [border, inner])

    // Layer 2: "Artwork" — a mix of shapes (drill points, circle, ellipse path).
    let artID = UUID()
    let drillPoints = (0..<8).map { i -> VectorPath in
        let cx = 80.0 + Double(i % 4) * 70
        let cy = 90.0 + Double(i / 4) * 90
        return VectorPath(
            id: UUID(), name: "Drill \(i + 1)",
            points: [VectorPoint(x: cx, y: cy)], isClosed: true, layerId: artID
        )
    }
    let circlePath = VectorPath(
        id: UUID(), name: "Decorative Circle",
        points: (0..<48).map { i in
            let a = Double(i) / 48 * 2 * .pi
            return VectorPoint(x: 200 + 40 * cos(a), y: 150 + 40 * sin(a))
        },
        isClosed: true, layerId: artID
    )
    // Ellipse via polygon approximation.
    let ellipsePath = VectorPath(
        id: UUID(), name: "Ellipse Motif",
        points: (0..<40).map { i in
            let a = Double(i) / 40 * 2 * .pi
            return VectorPoint(x: 300 + 55 * cos(a), y: 150 + 25 * sin(a))
        },
        isClosed: true, layerId: artID
    )
    let artLayer = Layer(id: artID, name: "Artwork", vectors: drillPoints + [circlePath, ellipsePath])

    // Layer 3: "Text" — glyph-style open polylines (SHOP letters, simplified).
    let textID = UUID()
    let glyphs = (0..<3).map { g -> VectorPath in
        let baseX = 60.0 + Double(g) * 70
        // Each glyph = a simple closed-ish path (H, O, P-ish simplified).
        return VectorPath(
            id: UUID(), name: "Glyph \(g)",
            points: [
                VectorPoint(x: baseX, y: 60), VectorPoint(x: baseX + 30, y: 60),
                VectorPoint(x: baseX + 30, y: 110), VectorPoint(x: baseX, y: 110),
                VectorPoint(x: baseX, y: 60),
            ],
            isClosed: true, layerId: textID
        )
    }
    let textLayer = Layer(id: textID, name: "Text", vectors: glyphs)

    let front = Sheet(name: "Front", width: stockW, depth: stockD, height: stockH,
                      layers: [borderLayer, artLayer, textLayer])

    // Sheet 2: "Back" — a pocket-only board (double-sided practice).
    let backID = UUID()
    let pocketBox = VectorPath(
        id: UUID(), name: "Pocket Area",
        points: [
            VectorPoint(x: 50, y: 50), VectorPoint(x: 350, y: 50),
            VectorPoint(x: 350, y: 250), VectorPoint(x: 50, y: 250),
            VectorPoint(x: 50, y: 50),
        ],
        isClosed: true, layerId: backID
    )
    let backLayer = Layer(id: backID, name: "Pocket", vectors: [pocketBox])
    let back = Sheet(name: "Back", width: stockW, depth: stockD, height: stockH, layers: [backLayer])

    let job = Job(name: "Master Test Job", sheets: [front, back])
    // Second sheet is active for the toolpaths below (Back → pocket).
    let activeSheet = back

    // ── Real toolpaths via engines ────────────────────────────────────────
    var toolpaths: [PersistedToolpath] = []

    // 1. Profile on the front border (outer rectangle).
    let profileParams = ProfileToolpathParams()
    let profileResult = ProfileToolpathEngine.compute(
        vectors: [border], params: profileParams, material: nil, stockHeightMm: stockH
    )
    toolpaths.append(PersistedToolpath(
        name: "Border Profile", toolpathResult: profileResult.gcodeLines.joined(separator: "\n"),
        estimatedTimeSeconds: profileResult.estimatedTimeSeconds, isDirty: false,
        paramsJSON: encodeJSON(profileParams)
    ))

    // 2. Pocket on the back sheet.
    let pocketParams = PocketToolpathParams()
    let pocketResult = PocketToolpathEngine.compute(
        vectors: [pocketBox], params: pocketParams, material: nil, stockHeightMm: stockH
    )
    toolpaths.append(PersistedToolpath(
        name: "Back Pocket", toolpathResult: pocketResult.gcodeLines.joined(separator: "\n"),
        estimatedTimeSeconds: pocketResult.estimatedTimeSeconds, isDirty: false,
        paramsJSON: encodeJSON(pocketParams)
    ))

    // 3. Drill on the 8 points.
    let drillParams = DrillToolpathParams()
    let drillPoints3D = drillPoints.map { p in
        DrillPoint(x: p.points[0].x, y: p.points[0].y, zDepthMm: 4, dwellSeconds: 0)
    }
    let drillResult = DrillToolpathEngine.compute(
        points: drillPoints3D, params: drillParams, material: nil, stockHeightMm: stockH
    )
    toolpaths.append(PersistedToolpath(
        name: "Hole Pattern", toolpathResult: drillResult.gcodeLines.joined(separator: "\n"),
        estimatedTimeSeconds: drillResult.estimatedTimeSeconds, isDirty: false,
        paramsJSON: encodeJSON(drillParams)
    ))

    // 4. V-Carve on the text glyphs.
    let vcarveParams = VCarveParams()
    let vcarveResult = VCarveEngine.compute(
        vectors: glyphs, params: vcarveParams, stockHeightMm: stockH
    )
    toolpaths.append(PersistedToolpath(
        name: "Text V-Carve", toolpathResult: vcarveResult.gcodeLines.joined(separator: "\n"),
        estimatedTimeSeconds: vcarveResult.estimatedTimeSeconds, isDirty: false,
        paramsJSON: encodeJSON(vcarveParams)
    ))

    // 5. Keep the border profile intentionally DIRTY (tests recalc + dirty gating).
    toolpaths.append(PersistedToolpath(
        name: "Dirty Placeholder", toolpathResult: "", estimatedTimeSeconds: 0,
        isDirty: true, paramsJSON: encodeJSON(profileParams)
    ))

    let payload = ShopPilotPackagePayload(job: job, toolpaths: toolpaths)
    return (payload, activeSheet.name)
}

// ── main ──────────────────────────────────────────────────────────────────
let fixturesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("fixtures")
    .appendingPathComponent("testpack")

try FileManager.default.createDirectory(at: fixturesRoot, withIntermediateDirectories: true)

let saver = DocumentSaver()
let loader = DocumentLoader()

let (payload, activeName) = makeMasterJob()
let outURL = fixturesRoot.appendingPathComponent("MasterTest.shoppilot")
try? FileManager.default.removeItem(at: outURL)
try saver.save(payload, to: outURL)

// Round-trip prove: load it back and assert structure.
let loaded = try loader.loadPayload(from: outURL)
guard loaded.job.name == "Master Test Job" else { fail("name round-trip") }
guard loaded.job.sheets.count == 2 else { fail("expected 2 sheets, got \(loaded.job.sheets.count)") }
let frontSheet = loaded.job.sheets.first { $0.name == "Front" }
guard let frontSheet, frontSheet.layers.count == 3 else { fail("front layers round-trip") }
let backSheet = loaded.job.sheets.first { $0.name == "Back" }
guard let backSheet else { fail("back sheet round-trip") }
guard loaded.toolpaths.count == 5 else { fail("expected 5 toolpaths, got \(loaded.toolpaths.count)") }
let dirtyCount = loaded.toolpaths.filter { $0.isDirty }.count
guard dirtyCount == 1 else { fail("expected 1 dirty toolpath, got \(dirtyCount)") }

print("MasterTest.shoppilot OK — sheets=\(loaded.job.sheets.count) (Front: \(frontSheet.layers.count) layers, Back: 1), "
      + "toolpaths=\(loaded.toolpaths.count) (profile/pocket/drill/vcarve + 1 dirty), "
      + "gcode-lines=\(loaded.toolpaths.prefix(4).compactMap { $0.toolpathResult?.components(separatedBy: .newlines).count }.reduce(0, +))")
print("TESTPACK-GEN DONE")

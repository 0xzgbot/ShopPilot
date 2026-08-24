import Foundation
import ShopPilotCore

/// SPK-2000b verify — cabinetry CSV import across six vendor dialects.
///
/// Covers: per-vocabulary header mapping (comma + tab), quoted cells,
/// quantity expansion into non-overlapping closed rectangles that fit the
/// sheet, honest failure on garbage input, and vectorPaths naming.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func fixture(_ text: String) -> Data {
    Data(text.utf8)
}

// Six vendor-flavored fixtures (real-world vocabulary, not invented columns).
let mozaik = fixture("""
"Part Name","Qty","Width","Height","Thickness"
"Side Panel",2,"600","720","18"
"Bottom",1,"564","600","18"
""")

let kcdTab = fixture("Part\tDim A\tDim B\tMaterial Thickness\tQty\nLeft Side\t580\t740\t18\t2\nShelf\t564\t280\t18\t3\n")

let cabinetSense = fixture("""
Component,Finished Size W,Finished Size H,Material,Qty
Door Front,397,716,3/4 Maple,2
Top Stretcher,568,100,3/4 Maple,1
""")

let cabinetPartsPro = fixture("""
Part Name,Grain Direction Length,Width Across Grain,Thickness,Quantity
Back Panel,740,564,0.75in,1
""")

let polyboard = fixture("""
Label;Number;L (Length);H (Height);T (Thickness)
Carcase Side;2;720;600;19
""")

let smartwop = fixture("""
Bezeichnung;Anzahl;Laenge;Breite;Staerke
Bodenteil;1;564;560;19
""")

// Malformed inputs.
let emptyFile = Data()
let gibberish = fixture("random,text,with,no,cnc,vocabulary\n1,2,3\n")
let partialNumbers = fixture("""
Part Name,Qty,Width,Height,Thickness
Broken Part,1,abc,720,18
Good Part,1,400,300,18
""")

func verify() throws {
    var dialectsSeen: Set<String> = []

    // 1. Mozaik — comma + quoted headers.
    let r1 = CabinetryImporter.importCSV(mozaik)
    try expect(r1.success, "mozaik parses (\(r1.errorMessage ?? ""))")
    try expect(r1.parts.count == 2 && r1.parts[0].quantity == 2, "mozaik parts+qty correct")
    try expect(abs(r1.parts[0].widthMm - 600) < 0.01, "mozaik width parsed")
    dialectsSeen.insert(r1.vendorDialect)

    // 2. KCD — tab separated.
    let r2 = CabinetryImporter.importCSV(kcdTab)
    try expect(r2.success, "kcd parses (\(r2.errorMessage ?? ""))")
    try expect(r2.parts.count == 2, "kcd part count")
    try expect(r2.parts[1].quantity == 3, "kcd shelf qty=3 expands to 3 rectangles")
    try expect(r2.rectangles.count == 5, "kcd total placed = 2 sides + 3 shelves (got \(r2.rectangles.count))")
    dialectsSeen.insert(r2.vendorDialect)

    // 3. CabinetSense.
    let r3 = CabinetryImporter.importCSV(cabinetSense)
    try expect(r3.success, "cabinetsense parses (\(r3.errorMessage ?? ""))")
    try expect(abs(r3.parts[0].heightMm - 716) < 0.01, "cabinetsense height parsed")
    dialectsSeen.insert(r3.vendorDialect)

    // 4. CabinetPartsPro — inch thickness string must not block numeric W/H.
    let r4 = CabinetryImporter.importCSV(cabinetPartsPro)
    try expect(r4.success, "cabinetpartspro parses (\(r4.errorMessage ?? ""))")
    try expect(r4.rectangles.count == 1, "cpp one rectangle")
    dialectsSeen.insert(r4.vendorDialect)

    // 5. Polyboard — semicolon separated with parenthesized headers.
    let r5 = CabinetryImporter.importCSV(polyboard)
    try expect(r5.success, "polyboard parses (\(r5.errorMessage ?? ""))")
    try expect(r5.parts[0].quantity == 2, "polyboard qty from Number column")
    dialectsSeen.insert(r5.vendorDialect)

    // 6. SmartWOP — German vocabulary, semicolons.
    let r6 = CabinetryImporter.importCSV(smartwop)
    try expect(r6.success, "smartwop parses (\(r6.errorMessage ?? ""))")
    try expect(r6.parts.count == 1, "smartwop part count")
    dialectsSeen.insert(r6.vendorDialect)

    try expect(dialectsSeen.count == 6, "all six vendor dialects matched distinctly (got \(dialectsSeen.sorted()))")

    // Geometry invariants on the biggest result: closed loops inside the sheet,
    // no pairwise overlap between placed rectangles.
    for r in [r1, r2, r3, r5] {
        for rect in r.rectangles {
            try expect(rect.count == 5 && rect.first == rect.last, "rectangle closed loop (first==last)")
            for p in rect {
                try expect(p.x >= 0 && p.x <= r.sheetWidthMm && p.y >= 0 && p.y <= r.sheetHeightMm,
                           "rectangle inside sheet bounds")
            }
        }
        // Overlap check (axis-aligned rects).
        func bounds(_ rect: [VectorPoint]) -> (Double, Double, Double, Double) {
            let xs = rect.map(\.x), ys = rect.map(\.y)
            return (xs.min()!, ys.min()!, xs.max()!, ys.max()!)
        }
        for i in 0..<r.rectangles.count {
            for j in (i + 1)..<r.rectangles.count {
                let a = bounds(r.rectangles[i]), b = bounds(r.rectangles[j])
                let overlaps = a.0 < b.2 - 0.001 && b.0 < a.2 - 0.001
                    && a.1 < b.3 - 0.001 && b.1 < a.3 - 0.001
                try expect(!overlaps, "rectangles \(i) and \(j) do not overlap")
            }
        }
    }

    // Honest failures.
    let e1 = CabinetryImporter.importCSV(emptyFile)
    try expect(!e1.success && e1.errorMessage != nil, "empty file fails honestly")
    let e2 = CabinetryImporter.importCSV(gibberish)
    try expect(!e2.success, "gibberish fails vocabulary match")
    let e3 = CabinetryImporter.importCSV(partialNumbers)
    try expect(!e3.success && e3.errorMessage?.contains("Row 2") == true,
               "partial-number row reported honestly (\(e3.errorMessage ?? ""))")

    // vectorPaths conversion: names carry copy suffixes when qty > 1.
    let paths = CabinetryImporter.vectorPaths(from: r1, layerId: UUID())
    try expect(paths.count == 3, "vectorPaths expanded count (got \(paths.count))")
    try expect(paths.contains { $0.name.contains("Side Panel 2") }, "copy-suffixed name present")
    try expect(paths.allSatisfy { $0.isClosed }, "paths closed")
}

do {
    try verify()
    print("ShopPilotVerify2000b: PASS — six vendor dialects parse, geometry fits/no-overlap/closed, failures honest, names expand")
} catch {
    print("ShopPilotVerify2000b: FAIL — \(error)")
    exit(1)
}

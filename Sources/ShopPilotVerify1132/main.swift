import Foundation
import ShopPilotCore

/// SPK-1132 verify (CLT machines, no XCTest).
/// Stock sheet presets — the 72-preset catalog (6 imperial × 6 thickness,
/// 6 metric × 6 thickness), preset application to a Sheet, name lookup,
/// and `.shoppilot`-style Codable round-trip of the preset selection.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func close(_ a: Double, _ b: Double, epsilon: Double = 0.001) -> Bool {
    abs(a - b) < epsilon
}

func main() throws {
    // 1. Catalog size: exactly 72 presets, 36 imperial + 36 metric.
    try expect(StockSheetPresets.all.count == 72, "catalog has 72 presets")
    try expect(StockSheetPresets.imperial.count == 36, "36 imperial presets")
    try expect(StockSheetPresets.metric.count == 36, "36 metric presets")

    // 2. Unique names (the persistence key).
    let names = Set(StockSheetPresets.all.map(\.name))
    try expect(names.count == 72, "all preset names unique")

    // 3. Imperial goldens — exact conversions (1 ft = 304.8 mm; 1 in = 25.4 mm).
    let fourByEight = StockSheetPresets.preset(named: "4'x8'x0.375''")
    try expect(fourByEight != nil, "4'x8'x0.375'' preset exists")
    if let p = fourByEight {
        try expect(close(p.widthMM, 1219.2) && close(p.depthMM, 2438.4),
                   "4'x8' = 1219.2 x 2438.4 mm (got \(p.widthMM) x \(p.depthMM))")
        try expect(close(p.thicknessMM, 9.525), "0.375'' = 9.525 mm (got \(p.thicknessMM))")
        try expect(!p.isMetric, "imperial preset flagged imperial")
    }
    let twoByTwo = StockSheetPresets.preset(named: "2'x2'x0.125''")
    if let p = twoByTwo {
        try expect(close(p.widthMM, 609.6) && close(p.depthMM, 609.6),
                   "2'x2' = 609.6 x 609.6 mm")
        try expect(close(p.thicknessMM, 3.175), "0.125'' = 3.175 mm")
    }
    let eightByFourThick = StockSheetPresets.preset(named: "8'x4'x1''")
    if let p = eightByFourThick {
        try expect(close(p.widthMM, 2438.4) && close(p.depthMM, 1219.2),
                   "8'x4' = 2438.4 x 1219.2 mm")
        try expect(close(p.thicknessMM, 25.4), "1'' = 25.4 mm")
    }

    // 4. Metric goldens.
    let metricSheet = StockSheetPresets.preset(named: "1219x2438x18 mm")
    try expect(metricSheet != nil, "1219x2438x18 mm preset exists")
    if let p = metricSheet {
        try expect(close(p.widthMM, 1219) && close(p.depthMM, 2438),
                   "1219x2438 dims correct")
        try expect(close(p.thicknessMM, 18), "18 mm thickness")
        try expect(p.isMetric, "metric preset flagged metric")
    }
    let smallMetric = StockSheetPresets.preset(named: "610x610x3 mm")
    if let p = smallMetric {
        try expect(close(p.widthMM, 610) && close(p.depthMM, 610) && close(p.thicknessMM, 3),
                   "610x610x3 mm dims correct")
    }
    let bigMetric = StockSheetPresets.preset(named: "2438x1219x25 mm")
    if let p = bigMetric {
        try expect(close(p.widthMM, 2438) && close(p.depthMM, 1219) && close(p.thicknessMM, 25),
                   "2438x1219x25 mm dims correct")
    }

    // 5. Structural completeness — every size × every thickness present.
    let imperialNames = Set(StockSheetPresets.imperial.map(\.name))
    for size in StockSheetPresets.imperialSizes {
        for thickness in StockSheetPresets.imperialThicknesses {
            let expected = "\(size.name)x\(thickness.label)''"
            try expect(imperialNames.contains(expected), "imperial preset \(expected) present")
        }
    }
    let metricNames = Set(StockSheetPresets.metric.map(\.name))
    for size in StockSheetPresets.metricSizes {
        for thickness in StockSheetPresets.metricThicknesses {
            let expected = "\(size.name)x\(Int(thickness)) mm"
            try expect(metricNames.contains(expected), "metric preset \(expected) present")
        }
    }

    // 6. Unknown lookup → nil.
    try expect(StockSheetPresets.preset(named: "nope") == nil, "unknown name is nil")
    try expect(StockSheetPresets.preset(named: "") == nil, "empty name is nil")

    // 7. Apply to a sheet: name, W/D/H, and preset name recorded.
    var sheet = Sheet(name: "Custom", width: 100, depth: 100, height: 10)
    let preset = StockSheetPresets.preset(named: "4'x4'x0.5''")!
    StockSheetPresets.apply(preset, to: &sheet)
    try expect(sheet.name == "4'x4'x0.5''", "sheet renamed to preset")
    try expect(close(sheet.width, 1219.2) && close(sheet.depth, 1219.2) && close(sheet.height, 12.7),
               "sheet dims applied (got \(sheet.width)x\(sheet.depth)x\(sheet.height))")
    try expect(sheet.stockPresetName == "4'x4'x0.5''", "stockPresetName recorded")

    // 8. Persistence — Codable round-trip preserves the preset choice
    //    (this is what `.shoppilot` save/open uses).
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(sheet)
    let restored = try decoder.decode(Sheet.self, from: data)
    try expect(restored.stockPresetName == "4'x4'x0.5''", "round-trip keeps stockPresetName")
    try expect(close(restored.width, 1219.2), "round-trip keeps width")

    // 9. Backward compatibility — decoding a sheet WITHOUT the new key
    //    (old documents) yields stockPresetName == nil.
    let legacyJSON = """
    {"id":"\(UUID().uuidString)","name":"Old Sheet","width":600,"depth":400,"height":25,"layers":[],"isDoubleSided":false}
    """
    let legacy = try decoder.decode(Sheet.self, from: Data(legacyJSON.utf8))
    try expect(legacy.stockPresetName == nil, "legacy doc decodes with nil preset")

    print("PASS — SPK-1132: 72 presets (\(StockSheetPresets.imperial.count) imperial, "
        + "\(StockSheetPresets.metric.count) metric), apply + round-trip verified.")
}

do {
    try main()
} catch {
    print("FAIL — \(error)")
    exit(1)
}

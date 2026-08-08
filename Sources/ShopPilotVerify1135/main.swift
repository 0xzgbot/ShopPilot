import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1135 verify (CLT machines, no XCTest).
/// Proves the HTML job-sheet template engine (`JobSheetHTMLTemplateEngine`):
///   1. Golden: the filled bundled template contains the job name, material,
///      sheet dimensions, and per-toolpath name / tool / feed / depth / time.
///   2. Toolpath rows: one <tr> per toolpath with all six cells populated.
///   3. HTML escaping: user content (& < > " ') cannot inject markup.
///   4. Strategy label mapping: Pocket/Drill/V-Carve/Quick Engrave classify
///      correctly; unknown labels fall back to the generic bucket.
///   5. Node accessors (SPK-1135): typeLabel, paramFeedRate, paramCutDepth
///      decode from a real Profile node's stored params.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func sampleData() -> JobSheetData {
    JobSheetData(
        jobName: "Test Coaster",
        material: "Hardwood — Oak",
        sheetWidth: 100,
        sheetHeight: 150,
        toolpaths: [
            ToolpathInfo(name: "Outline Cut", type: .profile, tool: "1/8\" End Mill",
                         feedRate: 1200, depth: 3.5, estimatedTime: 42.0),
            ToolpathInfo(name: "Text V-Carve", type: .vcarve, tool: "60° V-Bit",
                         feedRate: 800, depth: 2.0, estimatedTime: 18.0),
        ],
        createdAt: Date(timeIntervalSince1970: 1_752_000_000),
        notes: "Flip after first pass"
    )
}

func main() throws {
    let data = sampleData()
    let html = JobSheetHTMLTemplateEngine.fill(data: data)

    // ── 1. Golden content ─────────────────────────────────────────────────
    try expect(html.contains("Test Coaster"), "golden: job name present")
    try expect(html.contains("Hardwood — Oak"), "golden: material present")
    try expect(html.contains("100.0 × 150.0 mm"), "golden: sheet dims present")
    try expect(html.contains("Outline Cut"), "golden: toolpath name present")
    try expect(html.contains("1/8&quot; End Mill"), "golden: tool present (quote HTML-escaped)")
    try expect(html.contains("1200"), "golden: feed present")
    try expect(html.contains("3.50"), "golden: depth present (2dp)")
    try expect(html.contains("0.7"), "golden: time present (42s = 0.7 min)")
    try expect(html.contains("Flip after first pass"), "golden: notes present")
    try expect(html.contains("2"), "golden: toolpath count present")
    try expect(html.contains("@page { size: A4;"), "golden: A4 template present")

    // ── 2. Toolpath rows ──────────────────────────────────────────────────
    let rows = JobSheetHTMLTemplateEngine.toolpathRows(data.toolpaths)
    try expect(rows.components(separatedBy: "<tr>").count - 1 == 2, "one <tr> per toolpath")
    try expect(rows.contains("Text V-Carve"), "rows: second toolpath name")
    try expect(rows.contains("60° V-Bit"), "rows: second toolpath tool")
    try expect(rows.contains("800"), "rows: second toolpath feed")

    // ── 3. HTML escaping ──────────────────────────────────────────────────
    let evil = JobSheetData(
        jobName: "<script>alert('x')</script> & \"quoted\"",
        material: "Oak",
        sheetWidth: 10, sheetHeight: 10,
        toolpaths: [], notes: "a < b && c > d"
    )
    let evilHTML = JobSheetHTMLTemplateEngine.fill(data: evil)
    try expect(evilHTML.contains("&lt;script&gt;"), "escape: <script> neutralized")
    try expect(!evilHTML.contains("<script>"), "escape: no raw script tag")
    try expect(evilHTML.contains("&#39;"), "escape: single quote encoded")
    try expect(evilHTML.contains("&amp;"), "escape: ampersand encoded")
    try expect(evilHTML.contains("a &lt; b &amp;&amp; c &gt; d"), "escape: notes encoded")

    // ── 4. Strategy label mapping ─────────────────────────────────────────
    let labelType = ToolpathInfo.ToolpathType.self
    try expect(labelType.fromStrategyLabel("Pocket 1") == .pocket, "label: pocket")
    try expect(labelType.fromStrategyLabel("Drill") == .drill, "label: drill")
    try expect(labelType.fromStrategyLabel("V-Carve") == .vcarve, "label: vcarve")
    try expect(labelType.fromStrategyLabel("Quick Engrave") == .quickengrave, "label: quick engrave")
    try expect(labelType.fromStrategyLabel("Photo V-Carve") == .vcarve, "label: photo v-carve maps to vcarve")
    try expect(labelType.fromStrategyLabel("Rough 3D") == .profile, "label: unknown falls back to profile")

    // ── 5. Node accessors from stored params ──────────────────────────────
    let tree = ToolpathTreeManager()
    let profileNode = tree.addOperation("Profile Cut")
    let encoder = JSONEncoder()
    let profileParams = ProfileToolpathParams(
        feedRateMmPerMin: 1500, plungeFeedRateMmPerMin: 400,
        maxDepthOfCutMm: 4.0, spindleRpm: 12000
    )
    profileNode.paramsJSON = String(data: try encoder.encode(profileParams), encoding: .utf8)
    try expect(profileNode.typeLabel == "Profile Cut", "node: typeLabel")
    try expect(profileNode.strategyKind == ToolpathTreeNode.StrategyKind.profile, "node: strategy kind")
    try expect(abs((profileNode.paramFeedRate ?? 0) - 1500) < 1e-9, "node: paramFeedRate from JSON")
    try expect(abs((profileNode.paramCutDepth ?? 0) - 4.0) < 1e-9, "node: paramCutDepth from JSON")
    // A node with no stored params falls back to nil.
    let emptyNode = tree.addOperation("Bare")
    try expect(emptyNode.paramFeedRate == nil, "node: no params → nil feed")

    print("ShopPilotVerify1135: PASS — golden HTML content, toolpath rows, escaping, strategy mapping, node accessors")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1135: FAIL — \(error)")
    exit(1)
}

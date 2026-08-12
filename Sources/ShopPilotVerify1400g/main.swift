import Foundation
import ShopPilotCore

// SPK-1400g — inspector honesty.
//
// The Setup inspector's stock W/D/H fields are bound to the ACTIVE sheet and
// get their labels + formatting from a single Core seam (`Sheet.stockDimensions`
// / `StockDimension`). The selection badge shows real sheet/layer/toolpath
// names, never UUID prefixes. The Model inspector no longer claims a
// Studio3D-only lock. This CLT asserts the Core seam the inspector consumes.

enum VerifyError: Error { case failed(String) }

func expect(_ condition: Bool, _ message: String) throws {
    guard condition else { throw VerifyError.failed(message) }
}

func expectClose(_ a: Double, _ b: Double, _ message: String, tolerance: Double = 1e-9) throws {
    guard abs(a - b) <= tolerance else { throw VerifyError.failed("\(message): \(a) != \(b)") }
}

func main() throws {
    // 1. Stock-dimension seam: exactly three axes, inspector display order,
    //    with the labels the Setup inspector renders.
    let sheet = Sheet(name: "Sheet 1", width: 600, depth: 400, height: 25)
    let dims = sheet.stockDimensions
    try expect(dims.count == 3, "stockDimensions must have exactly 3 axes, got \(dims.count)")
    try expect(dims[0].label == "Width", "axis 0 label is 'Width', got '\(dims[0].label)'")
    try expect(dims[1].label == "Depth", "axis 1 label is 'Depth', got '\(dims[1].label)'")
    try expect(dims[2].label == "Height", "axis 2 label is 'Height', got '\(dims[2].label)'")

    // 2. Axis mapping — the inspector's commit routes each field to the right
    //    dimension (width/depth/height) on the ACTIVE sheet.
    try expect(dims[0].axis == .width, "axis 0 is .width")
    try expect(dims[1].axis == .depth, "axis 1 is .depth")
    try expect(dims[2].axis == .height, "axis 2 is .height")

    // 3. Values come from the sheet's real dimensions.
    try expectClose(dims[0].valueMm, 600, "axis 0 width value")
    try expectClose(dims[1].valueMm, 400, "axis 1 depth value")
    try expectClose(dims[2].valueMm, 25, "axis 2 height value")

    // 4. One-decimal formatting the inspector displays.
    try expect(dims[0].formatted == "600.0", "width formats to '600.0', got '\(dims[0].formatted)'")
    try expect(dims[1].formatted == "400.0", "depth formats to '400.0', got '\(dims[1].formatted)'")
    try expect(dims[2].formatted == "25.0", "height formats to '25.0', got '\(dims[2].formatted)'")

    // 5. A freshly-initialised job sheet (the "new job" path) still yields all
    //    three honest dimensions.
    var newJob = Job(name: "Untitled Job")
    _ = newJob.ensureSingleSheet()
    let defaults = newJob.sheets[0].stockDimensions
    try expect(defaults.count == 3, "default job sheet has 3 stock dimensions")
    try expect(defaults.allSatisfy { $0.formatted.isEmpty == false },
               "every stock dimension formats to a non-empty string")

    // 6. Sheets carry clean display names — the selection badge shows the
    //    name, not a UUID prefix.
    try expect(sheet.name == "Sheet 1", "sheet display name is 'Sheet 1', got '\(sheet.name)'")
    let renamed = Sheet(name: "Front", width: 600, depth: 400, height: 25)
    try expect(renamed.name == "Front", "custom sheet display name survives construction")
    try expect(renamed.stockDimensions.map(\.formatted) == ["600.0", "400.0", "25.0"],
               "renamed sheet stock formatting unchanged")

    print("1400g: PASS — inspector honesty")
}

do {
    try main()
} catch {
    print("1400g: FAIL — \(error)")
    exit(1)
}

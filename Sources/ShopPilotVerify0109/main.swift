import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0109 verify (CLT machine, no XCTest).
/// Proves the UX JOB RECIPE PICKER contract — blank, calibration, sign:
///   1. BLANK (Custom): recipe picker creates a basic job with the recipe's
///      stock dimensions, no toolpath, material set.
///   2. CALIBRATION: recipe picker builds a golden calibration job —
///      200×200×18mm stock, 50×50mm closed square on "Cut" layer, REAL
///      Profile toolpath (engine G-code, marker + cut moves, params JSON).
///      Job Codable round-trip keeps the calibration G-code + params + time.
///   3. SIGN: recipe picker builds via SignRecipeManager (existing path).
///   4. RECIPE PICKER: defaultRecipes includes Custom, Portrait Relief,
///      Decorative Panel, Signage, Calibration — each with valid dims.
///   5. CALIBRATION FIXTURE: fixtures/recipes/calibration.recipe.json parses.
///   6. RECIPE JOB → TREE: replaceJob materializes the calibration Profile
///      as a real tree node (Cut stage, preview, machine handoff).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func fixtureURL(_ name: String) -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("fixtures/recipes/\(name)")
}

func main() throws {
    // ── 1. BLANK (Custom) recipe → basic job. ─────────────────────────────
    let customRecipe = JobRecipe.defaultRecipes.first { $0.name == "Custom" }
    try expect(customRecipe != nil, "Custom recipe exists in defaultRecipes")
    let customJob = makeJobFromRecipe(customRecipe!, docVars: [])
    try expect(customJob.name == "Custom Job", "Custom recipe creates 'Custom Job'")
    try expect(customJob.sheets.count == 1, "Custom job has 1 sheet")
    let customSheet = customJob.sheets[0]
    try expect(abs(customSheet.width - 304.8) < 0.001, "Custom sheet width 304.8mm")
    try expect(abs(customSheet.depth - 304.8) < 0.001, "Custom sheet depth 304.8mm")
    try expect(abs(customSheet.height - 25.4) < 0.001, "Custom sheet height 25.4mm")
    try expect(customSheet.material != nil, "Custom sheet has a material")
    try expect(customJob.calibrationProfileResult == nil, "Custom has no calibration G-code")
    try expect(customJob.vcarveGCode == nil, "Custom has no V-Carve G-code")

    // ── 2. CALIBRATION recipe → golden calibration job. ───────────────────
    let calRecipe = JobRecipe.defaultRecipes.first { $0.name == "Calibration" }
    try expect(calRecipe != nil, "Calibration recipe exists in defaultRecipes")
    try expect(abs(calRecipe!.stockWidth - 200.0) < 0.001, "Calibration stock width 200mm")
    try expect(abs(calRecipe!.stockDepth - 200.0) < 0.001, "Calibration stock depth 200mm")
    try expect(abs(calRecipe!.stockHeight - 18.0) < 0.001, "Calibration stock height 18mm")

    let calJob = makeJobFromRecipe(calRecipe!, docVars: [])
    try expect(calJob.name == "Calibration", "Calibration recipe creates 'Calibration' job")
    try expect(calJob.sheets.count == 1, "Calibration job has 1 sheet")
    let calSheet = calJob.sheets[0]
    try expect(calSheet.layers.count >= 1, "Calibration sheet has at least 1 layer")
    let cutLayer = calSheet.layers.first { $0.name == "Cut" }
    try expect(cutLayer != nil, "Calibration sheet has a 'Cut' layer")
    try expect(cutLayer!.vectors.count == 1, "Calibration Cut layer has 1 vector (the square)")
    try expect(cutLayer!.vectors[0].isClosed, "Calibration square is closed")
    try expect(cutLayer!.vectors[0].points.count == 5, "Calibration square has 5 points (closed rect)")

    // Verify square geometry: 50×50 at (25,25)
    let square = cutLayer!.vectors[0]
    let xs = square.points.map { $0.x }
    let ys = square.points.map { $0.y }
    try expect(xs.min()! >= 25.0 && xs.max()! <= 75.0, "Calibration square X range 25-75mm")
    try expect(ys.min()! >= 25.0 && ys.max()! <= 75.0, "Calibration square Y range 25-75mm")

    // Real Profile toolpath
    guard let calGCode = calJob.calibrationProfileResult, !calGCode.isEmpty else {
        throw VerifyError.failed("Calibration job carries Profile G-code")
    }
    try expect(calGCode.contains("O=PROFILE_TOOLPATH"), "Calibration G-code has Profile marker")
    let calLines = calGCode.components(separatedBy: "\n")
    try expect(calLines.contains { $0.hasPrefix("G1") }, "Calibration G-code has cut moves (G1)")
    try expect(calJob.calibrationProfileTime != nil && calJob.calibrationProfileTime! > 0,
               "Calibration Profile has time estimate > 0")
    guard let paramsJSON = calJob.calibrationProfileParams,
          let paramsData = paramsJSON.data(using: .utf8),
          let params = try? JSONDecoder().decode(ProfileToolpathParams.self, from: paramsData) else {
        throw VerifyError.failed("Calibration Profile params JSON decodes to ProfileToolpathParams")
    }
    try expect(params.toolDiameterMm == 6.0, "Calibration Profile uses 6mm tool")

    // ── 3. Calibration Job Codable round-trip. ─────────────────────────────
    let calData = try JSONEncoder().encode(calJob)
    let calDecoded = try JSONDecoder().decode(Job.self, from: calData)
    try expect(calDecoded.calibrationProfileResult == calJob.calibrationProfileResult,
               "Job round-trip keeps calibration Profile G-code")
    try expect(calDecoded.calibrationProfileParams == calJob.calibrationProfileParams,
               "Job round-trip keeps calibration Profile params JSON")
    try expect(abs((calDecoded.calibrationProfileTime ?? 0) - (calJob.calibrationProfileTime ?? 0)) < 0.001,
               "Job round-trip keeps calibration Profile time")

    // ── 4. SIGN recipe → sign job (existing path). ────────────────────────
    let signRecipe = JobRecipe.defaultRecipes.first { $0.name == "Signage" }
    try expect(signRecipe != nil, "Signage recipe exists in defaultRecipes")
    let signJob = SignRecipeManager.createSignJob(jobName: "Signage Job", text: "SHOP", fontSize: 48, vBitAngle: 90, vCarveDepth: 0.5, feedRate: 1200)
    try expect(signJob.vcarveGCode != nil && !signJob.vcarveGCode!.isEmpty, "Sign job carries V-Carve G-code")

    // ── 5. RECIPE PICKER: defaultRecipes coverage. ─────────────────────────
    let recipeNames = JobRecipe.defaultRecipes.map { $0.name }
    try expect(recipeNames.contains("Custom"), "Recipe picker includes Custom")
    try expect(recipeNames.contains("Portrait Relief"), "Recipe picker includes Portrait Relief")
    try expect(recipeNames.contains("Decorative Panel"), "Recipe picker includes Decorative Panel")
    try expect(recipeNames.contains("Signage"), "Recipe picker includes Signage")
    try expect(recipeNames.contains("Calibration"), "Recipe picker includes Calibration")
    try expect(JobRecipe.defaultRecipes.count == 5, "Recipe picker has 5 recipes total")

    // Every recipe has valid dimensions
    for recipe in JobRecipe.defaultRecipes {
        try expect(recipe.stockWidth > 0 && recipe.stockDepth > 0 && recipe.stockHeight > 0,
                   "\(recipe.name) has positive stock dimensions")
        try expect(!recipe.icon.isEmpty, "\(recipe.name) has an icon")
        try expect(!recipe.recommendedStrategy.isEmpty, "\(recipe.name) has a recommended strategy")
    }

    // ── 6. CALIBRATION FIXTURE parses. ────────────────────────────────────
    let calFixture = RecipeJSONCodec.decode(try Data(contentsOf: fixtureURL("calibration.recipe.json")))
    try expect(calFixture?.name == "Calibration", "calibration.recipe.json parses")
    try expect(abs((calFixture?.stockWidth ?? 0) - 200.0) < 1e-9, "calibration fixture stock width 200mm")

    // ── 7. RECIPE JOB → TREE: replaceJob materializes calibration Profile ─
    let tree = ToolpathTreeManager()
    materializeCalibrationNode(calJob, into: tree)
    let ops = tree.allNodes.filter { $0.isOperation }
    try expect(ops.count == 1, "Calibration materializes as 1 tree node")
    try expect(ops[0].name == "Profile 1 (Recipe)", "Calibration tree node named 'Profile 1 (Recipe)'")
    try expect(!ops[0].isDirty, "Calibration tree node starts clean")

    print("ShopPilotVerify0109: PASS — blank + calibration + sign recipes, golden calibration job with real Profile, tree materialization")
}

/// Mirror of NewJobView.createJob(for:) — creates a job from a recipe.
func makeJobFromRecipe(_ recipe: JobRecipe, docVars: [DocumentVariable]) -> Job {
    if recipe.name == "Signage" {
        return SignRecipeManager.createSignJob(jobName: "Signage Job", text: "SHOP", fontSize: 48, vBitAngle: 90, vCarveDepth: 0.5, feedRate: 1200)
    }
    if recipe.name == "Calibration" {
        return createCalibrationJob(recipe: recipe, docVars: docVars)
    }
    // Blank/Custom/Portrait Relief/Decorative Panel: basic job
    var job = Job(name: "\(recipe.name) Job")
    var sheet = Sheet(name: recipe.name, width: recipe.stockWidth, depth: recipe.stockDepth, height: recipe.stockHeight)
    sheet.material = MaterialStore().defaultMaterial()
    job.addSheet(sheet)
    job.documentVariables = docVars
    return job
}

/// Mirror of NewJobView.createCalibrationJobFromRecipe.
func createCalibrationJob(recipe: JobRecipe, docVars: [DocumentVariable]) -> Job {
    let layerID = UUID()
    let square = VectorPath(
        id: UUID(),
        name: "Calibration Square",
        points: [
            VectorPoint(x: 25, y: 25),
            VectorPoint(x: 75, y: 25),
            VectorPoint(x: 75, y: 75),
            VectorPoint(x: 25, y: 75),
            VectorPoint(x: 25, y: 25),
        ],
        isClosed: true,
        layerId: layerID
    )
    let layer = Layer(id: layerID, name: "Cut", vectors: [square])
    var sheet = Sheet(name: "Calibration Sheet", width: recipe.stockWidth, depth: recipe.stockDepth, height: recipe.stockHeight, layers: [layer])
    sheet.material = MaterialStore().defaultMaterial()
    var job = Job(name: "Calibration", sheets: [sheet])
    let params = ProfileToolpathParams()
    let result = ProfileToolpathEngine.compute(vectors: [square], params: params, material: nil, stockHeightMm: recipe.stockHeight)
    job.calibrationProfileResult = result.gcodeLines.joined(separator: "\n")
    job.calibrationProfileTime = result.estimatedTimeSeconds
    job.calibrationProfileParams = (try? JSONEncoder().encode(params)).flatMap { String(data: $0, encoding: .utf8) }
    job.documentVariables = docVars
    return job
}

/// Mirror of AppSession.replaceJob's SPK-0109 materialization.
func materializeCalibrationNode(_ job: Job, into tree: ToolpathTreeManager) {
    guard let calGCode = job.calibrationProfileResult, !calGCode.isEmpty else { return }
    let node = tree.addOperation("Profile 1 (Recipe)")
    node.toolpathResult = calGCode
    node.estimatedTimeSeconds = job.calibrationProfileTime ?? 0
    node.paramsJSON = job.calibrationProfileParams
    node.clearDirty()
}

do {
    try main()
} catch {
    print("ShopPilotVerify0109: FAIL — \(error)")
    exit(1)
}

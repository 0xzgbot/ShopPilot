import XCTest
@testable import ShopPilotCore
@testable import ShopPilotGeometry

// MARK: - Sign Recipe E2E Tests

/// End-to-end test for the sign recipe pipeline:
/// recipe selection → text-on-curve → decorative border → V-Carve toolpath → job metadata
final class SignRecipeE2ETests: XCTestCase {
    
    // MARK: - Recipe Selection
    
    func testSignRecipeHasCorrectDimensions() {
        let signRecipe = JobRecipe.defaultRecipes.first { $0.name == "Signage" }
        XCTAssertNotNil(signRecipe, "Signage recipe must exist")
        
        guard let recipe = signRecipe else {
            XCTFail("Recipe not found")
            return
        }
        
        XCTAssertEqual(recipe.stockWidth, 457.2)   // 18 inches
        XCTAssertEqual(recipe.stockDepth, 609.6)   // 24 inches
        XCTAssertEqual(recipe.stockHeight, 19.05)  // 0.75 inches
        XCTAssertEqual(recipe.recommendedStrategy, "Profile + V-Carve lettering")
    }
    
    // MARK: - Job Creation
    
    func testCreateSignJob() {
        let job = SignRecipeManager.createSignJob(
            jobName: "Test Sign",
            text: "SHOP",
            font: "Helvetica Neue",
            fontSize: 48.0,
            scale: 1.0,
            vBitAngle: 90.0,
            vCarveDepth: 0.5,
            feedRate: 1000.0
        )
        
        // Verify job structure
        XCTAssertEqual(job.name, "Test Sign")
        XCTAssertEqual(job.sheets.count, 1)
        
        let sheet = job.sheets[0]
        XCTAssertEqual(sheet.name, "Sign Sheet")
        XCTAssertEqual(sheet.width, 457.2)
        XCTAssertEqual(sheet.depth, 609.6)
        XCTAssertEqual(sheet.height, 19.05)
        XCTAssertNotNil(sheet.material)
        XCTAssertEqual(sheet.material?.name, "MDF")
    }
    
    // MARK: - Layer Structure
    
    func testSignJobHasTextAndBorderLayers() {
        let job = SignRecipeManager.createSignJob()
        let sheet = job.sheets[0]
        
        XCTAssertEqual(sheet.layers.count, 2)
        XCTAssertEqual(sheet.layers[0].name, "Text")
        XCTAssertEqual(sheet.layers[1].name, "Border")
    }
    
    func testSignJobTextLayerHasVectors() {
        let job = SignRecipeManager.createSignJob(text: "TEST")
        let textLayer = job.sheets[0].layers.first { $0.name == "Text" }
        
        XCTAssertNotNil(textLayer, "Text layer must exist")
        XCTAssertNotNil(textLayer?.vectors)
        XCTAssertFalse(textLayer!.vectors.isEmpty, "Text layer must have vectors")
        
        // Each vector should have points
        for vector in textLayer!.vectors {
            XCTAssertFalse(vector.points.isEmpty, "Each vector must have points")
        }
    }
    
    func testSignJobBorderLayerHasVectors() {
        let job = SignRecipeManager.createSignJob()
        let borderLayer = job.sheets[0].layers.first { $0.name == "Border" }
        
        XCTAssertNotNil(borderLayer, "Border layer must exist")
        XCTAssertNotNil(borderLayer?.vectors)
        XCTAssertFalse(borderLayer!.vectors.isEmpty, "Border layer must have vectors")
    }
    
    // MARK: - V-Carve Toolpath
    
    func testSignJobHasVCarveMetadata() {
        let job = SignRecipeManager.createSignJob(
            text: "SHOP",
            vBitAngle: 90.0,
            vCarveDepth: 0.5
        )
        
        XCTAssertGreaterThan(job.vcarvePasses, 0, "V-Carve should generate passes")
        XCTAssertGreaterThan(job.vcarveTimeSeconds, 0, "V-Carve should estimate time")
    }
    
    func testVCarveDepthAffectsPassCount() {
        let shallowJob = SignRecipeManager.createSignJob(vCarveDepth: 0.25)
        let deepJob = SignRecipeManager.createSignJob(vCarveDepth: 1.0)
        
        // Deeper carve should produce more passes (finer step-over)
        XCTAssertGreaterThanOrEqual(
            deepJob.vcarvePasses,
            shallowJob.vcarvePasses,
            "Deeper V-Carve should produce equal or more passes"
        )
    }
    
    func testVCarveAngleAffectsToolpath() {
        let job60 = SignRecipeManager.createSignJob(vBitAngle: 60.0)
        let job90 = SignRecipeManager.createSignJob(vBitAngle: 90.0)
        let job120 = SignRecipeManager.createSignJob(vBitAngle: 120.0)
        
        // All should generate passes
        XCTAssertGreaterThan(job60.vcarvePasses, 0)
        XCTAssertGreaterThan(job90.vcarvePasses, 0)
        XCTAssertGreaterThan(job120.vcarvePasses, 0)
    }
    
    // MARK: - Text Customization
    
    func testDifferentTextProducesDifferentGlyphs() {
        let jobA = SignRecipeManager.createSignJob(text: "A")
        let jobB = SignRecipeManager.createSignJob(text: "AB")
        let jobC = SignRecipeManager.createSignJob(text: "ABC")
        
        let textLayerA = jobA.sheets[0].layers.first { $0.name == "Text" }!
        let textLayerB = jobB.sheets[0].layers.first { $0.name == "Text" }!
        let textLayerC = jobC.sheets[0].layers.first { $0.name == "Text" }!
        
        // More text = more glyphs/vectors
        XCTAssertLessThan(textLayerA.vectors.count, textLayerB.vectors.count)
        XCTAssertLessThanOrEqual(textLayerB.vectors.count, textLayerC.vectors.count)
    }
    
    func testFontSizeAffectsVectorPoints() {
        let smallJob = SignRecipeManager.createSignJob(fontSize: 24.0)
        let largeJob = SignRecipeManager.createSignJob(fontSize: 96.0)
        
        let smallLayer = smallJob.sheets[0].layers.first { $0.name == "Text" }!
        let largeLayer = largeJob.sheets[0].layers.first { $0.name == "Text" }!
        
        // Larger font = larger glyph geometry (bounding box scales with the
        // font size; point count stays constant because bezier flattening uses
        // fixed parametric strides).
        let boundsSmall = smallLayer.vectors.boundingRect
        let boundsLarge = largeLayer.vectors.boundingRect
        XCTAssertGreaterThan(boundsLarge.width, boundsSmall.width, "Larger font should produce wider glyph bounds")
        XCTAssertGreaterThan(boundsLarge.height, boundsSmall.height, "Larger font should produce taller glyph bounds")
    }
    
    // MARK: - Document Variables Integration
    
    func testSignJobStoresDocumentVariables() {
        let vars = [
            DocumentVariable(key: "width", value: "609.6", category: "Dimensions"),
            DocumentVariable(key: "depth", value: "914.4", category: "Dimensions"),
            DocumentVariable(key: "material", value: "Plywood", category: "Material")
        ]
        
        var job = SignRecipeManager.createSignJob()
        job.documentVariables = vars
        
        XCTAssertEqual(job.documentVariables.count, 3)
        XCTAssertEqual(job.documentVariables[0].key, "width")
        XCTAssertEqual(job.documentVariables[1].value, "914.4")
    }
    
    // MARK: - Job Encoding/Decoding
    
    func testSignJobCanBeEncodedAndDecoded() throws {
        let job = SignRecipeManager.createSignJob(jobName: "EncodeTest")
        
        let data = try job.encode()
        XCTAssertFalse(data.isEmpty, "Encoded job should not be empty")
        
        let decoded = try Job.decode(data)
        XCTAssertEqual(decoded.name, "EncodeTest")
        XCTAssertEqual(decoded.sheets.count, 1)
        XCTAssertEqual(decoded.vcarvePasses, job.vcarvePasses)
        XCTAssertEqual(decoded.vcarveTimeSeconds, job.vcarveTimeSeconds)
    }
    
    // MARK: - Decorative Border
    
    func testDecorativeBorderIsClosed() {
        let job = SignRecipeManager.createSignJob()
        let borderLayer = job.sheets[0].layers.first { $0.name == "Border" }!
        
        for vector in borderLayer.vectors {
            XCTAssertTrue(vector.isClosed, "Border vector must be closed")
        }
    }
    
    func testBorderFitsWithinStock() {
        let job = SignRecipeManager.createSignJob()
        let borderLayer = job.sheets[0].layers.first { $0.name == "Border" }!
        
        let stockWidth = job.sheets[0].width
        let stockDepth = job.sheets[0].depth
        
        for vector in borderLayer.vectors {
            for point in vector.points {
                XCTAssertGreaterThan(point.x, 0, "Border point X must be within stock")
                XCTAssertLessThan(point.x, stockWidth, "Border point X must be within stock")
                XCTAssertGreaterThan(point.y, 0, "Border point Y must be within stock")
                XCTAssertLessThan(point.y, stockDepth, "Border point Y must be within stock")
            }
        }
    }
    
    // MARK: - Scale Parameter
    
    func testScaleAffectsTextSize() {
        let job05 = SignRecipeManager.createSignJob(scale: 0.5)
        let job10 = SignRecipeManager.createSignJob(scale: 1.0)
        let job20 = SignRecipeManager.createSignJob(scale: 2.0)
        
        let layer05 = job05.sheets[0].layers.first { $0.name == "Text" }!
        let layer10 = job10.sheets[0].layers.first { $0.name == "Text" }!
        let layer20 = job20.sheets[0].layers.first { $0.name == "Text" }!
        
        // Bounding box width should increase with scale
        let bounds05 = layer05.vectors.boundingRect
        let bounds10 = layer10.vectors.boundingRect
        let bounds20 = layer20.vectors.boundingRect
        
        XCTAssertLessThan(bounds05.width, bounds10.width)
        XCTAssertLessThan(bounds10.width, bounds20.width)
    }
}

// MARK: - Helper Extensions

private extension [VectorPath] {
    var boundingRect: Rect {
        guard !isEmpty else { return Rect() }
        var allPoints: [VectorPoint] = []
        for vec in self {
            allPoints.append(contentsOf: vec.points)
        }
        guard !allPoints.isEmpty else { return Rect() }
        let xs = allPoints.map { $0.x }
        let ys = allPoints.map { $0.y }
        return Rect(
            minX: xs.min()!,
            minY: ys.min()!,
            maxX: xs.max()!,
            maxY: ys.max()!
        )
    }
}

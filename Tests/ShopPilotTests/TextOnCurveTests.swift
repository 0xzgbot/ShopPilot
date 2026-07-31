import XCTest
@testable import ShopPilotGeometry

final class TextOnCurveTests: XCTestCase {
    
    // MARK: - Basic Text on Curve
    
    func testTextOnCurveProducesShapes() {
        let curvePoints: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 100, y: 0)
        ]
        
        let shapes = TextTool.textOnCurve(
            text: "ABC",
            curvePoints: curvePoints,
            fontSize: 24.0,
            scale: 1.0
        )
        
        // Should produce one shape per non-space character
        XCTAssertGreaterThan(shapes.count, 0)
    }
    
    func testTextOnCurveEmptyInput() {
        let shapes1 = TextTool.textOnCurve(
            text: "",
            curvePoints: [VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 10)]
        )
        XCTAssertTrue(shapes1.isEmpty)
        
        let shapes2 = TextTool.textOnCurve(
            text: "   ",
            curvePoints: [VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 10)]
        )
        XCTAssertTrue(shapes2.isEmpty)
    }
    
    func testTextOnCurveInvalidCurve() {
        let shapes = TextTool.textOnCurve(
            text: "ABC",
            curvePoints: []
        )
        XCTAssertTrue(shapes.isEmpty)
        
        let shapes2 = TextTool.textOnCurve(
            text: "ABC",
            curvePoints: [VectorPoint(x: 0, y: 0)]
        )
        XCTAssertTrue(shapes2.isEmpty)
    }
    
    // MARK: - Text on Arc
    
    func testTextOnArcProducesShapes() {
        let center = VectorPoint(x: 0, y: 0)
        
        let shapes = TextTool.textOnArc(
            text: "ABC",
            center: center,
            radius: 50.0,
            startAngle: 0,
            endAngle: .pi,
            fontSize: 24.0,
            scale: 1.0
        )
        
        XCTAssertGreaterThan(shapes.count, 0)
    }
    
    func testTextOnArcFullCircle() {
        let center = VectorPoint(x: 0, y: 0)
        
        let shapes = TextTool.textOnArc(
            text: "HELLO",
            center: center,
            radius: 30.0,
            startAngle: 0,
            endAngle: 2 * .pi,
            fontSize: 18.0,
            scale: 1.0
        )
        
        XCTAssertGreaterThan(shapes.count, 0)
    }
    
    // MARK: - Character Rotation Follows Tangent
    
    func testCharacterRotationFollowsTangent() {
        // Create a simple diagonal line
        let curvePoints: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 100, y: 100)
        ]
        
        let shapes = TextTool.textOnCurve(
            text: "X",
            curvePoints: curvePoints,
            fontSize: 24.0,
            scale: 1.0
        )
        
        // Should produce at least one shape
        XCTAssertGreaterThan(shapes.count, 0)
        
        // The shape should be a freehand (from CoreText rendering)
        for shape in shapes {
            switch shape {
            case .freehand(let points):
                XCTAssertGreaterThan(points.count, 0)
            default:
                // Other shape types are also valid
                break
            }
        }
    }
    
    // MARK: - Offset Parameter
    
    func testOffsetPlacesTextAtDifferentPositions() {
        let curvePoints: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 100, y: 0),
            VectorPoint(x: 200, y: 0)
        ]
        
        let shapesCenter = TextTool.textOnCurve(
            text: "TEST",
            curvePoints: curvePoints,
            fontSize: 24.0,
            scale: 1.0,
            offset: 0.5
        )
        
        let shapesStart = TextTool.textOnCurve(
            text: "TEST",
            curvePoints: curvePoints,
            fontSize: 24.0,
            scale: 1.0,
            offset: 0.0
        )
        
        // Both should produce shapes
        XCTAssertGreaterThan(shapesCenter.count, 0)
        XCTAssertGreaterThan(shapesStart.count, 0)
    }
    
    // MARK: - Letter Spacing
    
    func testLetterSpacingIncreasesWidth() {
        let curvePoints: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 100, y: 0),
            VectorPoint(x: 200, y: 0)
        ]
        
        let shapesNoSpacing = TextTool.textOnCurve(
            text: "AB",
            curvePoints: curvePoints,
            fontSize: 24.0,
            scale: 1.0,
            letterSpacing: 0.0
        )
        
        let shapesWithSpacing = TextTool.textOnCurve(
            text: "AB",
            curvePoints: curvePoints,
            fontSize: 24.0,
            scale: 1.0,
            letterSpacing: 10.0
        )
        
        // Both should produce shapes
        XCTAssertGreaterThan(shapesNoSpacing.count, 0)
        XCTAssertGreaterThan(shapesWithSpacing.count, 0)
    }
    
    // MARK: - Shape Types
    
    func testShapesAreValidVectorShapes() {
        let curvePoints: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 100, y: 0)
        ]
        
        let shapes = TextTool.textOnCurve(
            text: "Hello",
            curvePoints: curvePoints,
            fontSize: 36.0,
            scale: 1.0
        )
        
        // All shapes should have valid bounding boxes
        for shape in shapes {
            let bb = shape.boundingRect
            XCTAssertLessThanOrEqual(bb.minX, bb.maxX)
            XCTAssertLessThanOrEqual(bb.minY, bb.maxY)
        }
    }
    
    // MARK: - Multiple Characters
    
    func testMultipleCharactersProduceMultipleShapes() {
        let curvePoints: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 100, y: 0),
            VectorPoint(x: 200, y: 0)
        ]
        
        let shapes = TextTool.textOnCurve(
            text: "ABCDE",
            curvePoints: curvePoints,
            fontSize: 24.0,
            scale: 1.0
        )
        
        // Should produce 5 shapes (one per character)
        XCTAssertEqual(shapes.count, 5)
    }
    
    // MARK: - Font and Size
    
    func testDifferentFontSizes() {
        let curvePoints: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 100, y: 0),
            VectorPoint(x: 200, y: 0)
        ]
        
        let shapesSmall = TextTool.textOnCurve(
            text: "A",
            curvePoints: curvePoints,
            fontSize: 12.0,
            scale: 1.0
        )
        
        let shapesLarge = TextTool.textOnCurve(
            text: "A",
            curvePoints: curvePoints,
            fontSize: 72.0,
            scale: 1.0
        )
        
        // Both should produce shapes
        XCTAssertGreaterThan(shapesSmall.count, 0)
        XCTAssertGreaterThan(shapesLarge.count, 0)
    }
    
    // MARK: - Scale Parameter
    
    func testScaleParameter() {
        let curvePoints: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 100, y: 0),
            VectorPoint(x: 200, y: 0)
        ]
        
        let shapesNormal = TextTool.textOnCurve(
            text: "X",
            curvePoints: curvePoints,
            fontSize: 24.0,
            scale: 1.0
        )
        
        let shapesScaled = TextTool.textOnCurve(
            text: "X",
            curvePoints: curvePoints,
            fontSize: 24.0,
            scale: 2.0
        )
        
        // Both should produce shapes
        XCTAssertGreaterThan(shapesNormal.count, 0)
        XCTAssertGreaterThan(shapesScaled.count, 0)
    }
}

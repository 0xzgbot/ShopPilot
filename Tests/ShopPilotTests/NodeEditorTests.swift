import XCTest
@testable import ShopPilotGeometry

final class NodeEditorTests: XCTestCase {

    // MARK: - moveVertex on .freehand (polyline)

    func testMoveVertexFreehand() {
        let pts = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 10, y: 0),
            VectorPoint(x: 10, y: 10)
        ]
        let shape = VectorShape.freehand(points: pts)

        let moved = shape.moveVertex(at: 1, to: VectorPoint(x: 5, y: 5))

        // Should return .freehand with the middle vertex changed
        if case .freehand(let newPts) = moved {
            XCTAssertEqual(newPts[0], VectorPoint(x: 0, y: 0), "first point unchanged")
            XCTAssertEqual(newPts[1], VectorPoint(x: 5, y: 5), "second point moved")
            XCTAssertEqual(newPts[2], VectorPoint(x: 10, y: 10), "third point unchanged")
        } else {
            XCTFail("Expected .freehand shape after moveVertex")
        }
    }

    func testMoveVertexFreehandOutOfBoundsReturnsSelf() {
        let pts = [VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0)]
        let shape = VectorShape.freehand(points: pts)

        // Out of range indices should return self unchanged
        let movedNeg = shape.moveVertex(at: -1, to: VectorPoint(x: 99, y: 99))
        let movedBig = shape.moveVertex(at: 100, to: VectorPoint(x: 99, y: 99))

        if case .freehand(let ptsNeg) = movedNeg {
            XCTAssertEqual(ptsNeg.count, 2, "should still have 2 points")
        } else {
            XCTFail("Expected .freehand")
        }

        if case .freehand(let ptsBig) = movedBig {
            XCTAssertEqual(ptsBig.count, 2, "should still have 2 points")
        } else {
            XCTFail("Expected .freehand")
        }
    }

    // MARK: - moveVertex on .line

    func testMoveVertexLineStart() {
        let shape = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 10))
        let moved = shape.moveVertex(at: 0, to: VectorPoint(x: 3, y: 3))

        if case .line(let s, let e) = moved {
            XCTAssertEqual(s, VectorPoint(x: 3, y: 3), "start moved")
            XCTAssertEqual(e, VectorPoint(x: 10, y: 10), "end unchanged")
        } else {
            XCTFail("Expected .line shape")
        }
    }

    func testMoveVertexLineEnd() {
        let shape = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 10))
        let moved = shape.moveVertex(at: 1, to: VectorPoint(x: 15, y: 20))

        if case .line(let s, let e) = moved {
            XCTAssertEqual(s, VectorPoint(x: 0, y: 0), "start unchanged")
            XCTAssertEqual(e, VectorPoint(x: 15, y: 20), "end moved")
        } else {
            XCTFail("Expected .line shape")
        }
    }

    func testMoveVertexLineInvalidIndexReturnsSelf() {
        let shape = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 10))
        let moved = shape.moveVertex(at: 5, to: VectorPoint(x: 99, y: 99))

        // Should return self for invalid index
        XCTAssertEqual(moved.hashValue, shape.hashValue, "invalid index should return self")
    }

    // MARK: - moveVertex on non-polyline shapes

    func testMoveVertexCircleReturnsSelf() {
        let shape = VectorShape.circle(center: VectorPoint(x: 5, y: 5), radius: 10)
        let moved = shape.moveVertex(at: 0, to: VectorPoint(x: 99, y: 99))
        XCTAssertEqual(moved.hashValue, shape.hashValue, "circle should return self")
    }

    func testMoveVertexRectangleReturnsSelf() {
        let shape = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 20)
        let moved = shape.moveVertex(at: 0, to: VectorPoint(x: 99, y: 99))
        XCTAssertEqual(moved.hashValue, shape.hashValue, "rectangle should return self")
    }

    // MARK: - ShapeNodeEditor moveNode

    func testShapeNodeEditorMoveNode() {
        let editor = ShapeNodeEditor()
        editor.addNode(at: VectorPoint(x: 0, y: 0))
        editor.addNode(at: VectorPoint(x: 10, y: 0))
        editor.addNode(at: VectorPoint(x: 10, y: 10))

        let firstId = editor.nodes[0].id
        editor.moveNode(id: firstId, to: VectorPoint(x: 5, y: 5))

        let movedNode = editor.getNode(id: firstId)
        XCTAssertNotNil(movedNode, "node should still exist")
        XCTAssertEqual(movedNode?.point, VectorPoint(x: 5, y: 5), "node moved to new position")
    }

    func testShapeNodeEditorRemoveNode() {
        let editor = ShapeNodeEditor()
        editor.addNode(at: VectorPoint(x: 0, y: 0))
        editor.addNode(at: VectorPoint(x: 10, y: 0))

        XCTAssertEqual(editor.nodes.count, 2, "two nodes added")

        let firstId = editor.nodes[0].id
        editor.removeNode(id: firstId)

        XCTAssertEqual(editor.nodes.count, 1, "one node removed")
        XCTAssertNil(editor.getNode(id: firstId), "removed node should not be found")
    }

    func testShapeNodeEditorClear() {
        let editor = ShapeNodeEditor()
        editor.addNode(at: VectorPoint(x: 0, y: 0))
        editor.addNode(at: VectorPoint(x: 10, y: 0))
        editor.clear()

        XCTAssertTrue(editor.nodes.isEmpty, "all nodes cleared")
    }

    // MARK: - extractNodes / updateFromNodes round-trip for freehand

    func testExtractAndUpdateFreehandRoundTrip() {
        let pts = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 10, y: 0),
            VectorPoint(x: 10, y: 10)
        ]
        let shape = VectorShape.freehand(points: pts)

        let nodes = shape.extractNodes()
        XCTAssertEqual(nodes.count, 3, "extracted 3 nodes from 3-point polyline")

        // Move the middle node
        nodes[1].point = VectorPoint(x: 5, y: 5)
        let updated = shape.updateFromNodes(nodes)

        if case .freehand(let newPts) = updated {
            XCTAssertEqual(newPts[0], pts[0], "first point unchanged")
            XCTAssertEqual(newPts[1], VectorPoint(x: 5, y: 5), "middle point updated")
            XCTAssertEqual(newPts[2], pts[2], "third point unchanged")
        } else {
            XCTFail("Expected .freehand after updateFromNodes")
        }
    }
}

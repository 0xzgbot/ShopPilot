import XCTest
@testable import ShopPilotCore

/// Unit tests for ProfileToolpathEngine — SPK-0302a.
final class ProfileToolpathTests: XCTestCase {

    /// Verify that a closed polyline produces a non-empty path with G1 segments.
    func testProfileToolpathClosedPolyPathReturnsG1Segments() {
        // Square closed polyline
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50),
            VectorPoint(x: 0, y: 50),
            VectorPoint(x: 0, y: 0)
        ]
        let vectorPath = VectorPath(points: points, isClosed: true)

        let params = ProfileToolpathParams(
            cutMode: .onCut,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            toolDiameterMm: 6.0,
            tabWidths: [],
            finishPasses: 1,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0
        )

        let result = ProfileToolpathEngine.compute(
            vectors: [vectorPath],
            params: params,
            material: nil,
            stockHeightMm: 12.0
        )

        // AC: path must be non-empty and contain G1 segments
        XCTAssertFalse(result.path.isEmpty, "path should not be empty for a closed polyline")
        XCTAssertTrue(result.path.contains { $0.hasPrefix("G1") }, "path should contain G1 cutting segments")

        // Also verify gcodeLines is non-empty
        XCTAssertFalse(result.gcodeLines.isEmpty)
        XCTAssertTrue(result.gcodeLines.contains { $0.hasPrefix("G1") })
    }
}

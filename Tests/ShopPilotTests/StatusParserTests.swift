import XCTest
@testable import ShopPilotCore

final class StatusParserTests: XCTestCase {

    // MARK: - Fixture 1: Idle with MPos

    func testIdleWithMPos() {
        let data = Data("<Idle|MPos:0.000,0.000,0.000|FS:0,0>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result, "Should parse GRBL status report")
        XCTAssertEqual(result?.state, "Idle")
        XCTAssertEqual(result?.mPosX, 0.0, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosY, 0.0, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosZ, 0.0, accuracy: 1e-3)
        XCTAssertEqual(result?.wPosX, 0.0, accuracy: 1e-3)
        XCTAssertEqual(result?.wPosY, 0.0, accuracy: 1e-3)
        XCTAssertEqual(result?.wPosZ, 0.0, accuracy: 1e-3)
    }

    // MARK: - Fixture 2: Running with non-zero MPos

    func testRunningWithMPos() {
        let data = Data("<Run|MPos:125.500,73.250,-2.000|FS:1500,24>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result, "Should parse GRBL status report")
        XCTAssertEqual(result?.state, "Run")
        XCTAssertEqual(result?.mPosX, 125.5, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosY, 73.25, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosZ, -2.0, accuracy: 1e-3)
    }

    // MARK: - Fixture 3: Hold with MPos and WPos

    func testHoldWithMPosAndWPos() {
        let data = Data("<Hold|MPos:50.000,100.000,5.000|WPos:48.500,98.750,3.250|FS:800,12>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result, "Should parse GRBL status report")
        XCTAssertEqual(result?.state, "Hold")
        XCTAssertEqual(result?.mPosX, 50.0, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosY, 100.0, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosZ, 5.0, accuracy: 1e-3)
        XCTAssertEqual(result?.wPosX, 48.5, accuracy: 1e-3)
        XCTAssertEqual(result?.wPosY, 98.75, accuracy: 1e-3)
        XCTAssertEqual(result?.wPosZ, 3.25, accuracy: 1e-3)
    }

    // MARK: - Fixture 4: Alarm state

    func testAlarmState() {
        let data = Data("<Alarm|MPos:0.000,0.000,0.000|FS:0,0>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result, "Should parse GRBL status report")
        XCTAssertEqual(result?.state, "Alarm")
        XCTAssertEqual(result?.mPosX, 0.0, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosY, 0.0, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosZ, 0.0, accuracy: 1e-3)
    }

    // MARK: - Fixture 5: Door state with MPos

    func testDoorState() {
        let data = Data("<Door|MPos:200.000,150.000,0.000|FS:0,0>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result, "Should parse GRBL status report")
        XCTAssertEqual(result?.state, "Door")
        XCTAssertEqual(result?.mPosX, 200.0, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosY, 150.0, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosZ, 0.0, accuracy: 1e-3)
    }

    // MARK: - FS (feed/spindle) parsing

    func testFSFeedAndSpindle() {
        let data = Data("<Run|MPos:10,20,30|FS:500,1200>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fs?.feed, 500.0, accuracy: 1e-3)
        XCTAssertEqual(result?.fs?.spindle, 1200.0, accuracy: 1e-3)
    }

    func testFSZeroValues() {
        let data = Data("<Idle|FS:0,0>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fs?.feed, 0.0, accuracy: 1e-3)
        XCTAssertEqual(result?.fs?.spindle, 0.0, accuracy: 1e-3)
    }

    // MARK: - Bf (buffer) parsing

    func testBufferField() {
        let data = Data("<Run|MPos:10,20,30|Bf:15>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.buffer, 15)
    }

    func testBufferZero() {
        let data = Data("<Idle|Bf:0>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.buffer, 0)
    }

    // MARK: - Pn (pins) parsing

    func testPinsAllClear() {
        let data = Data("<Idle|Pn:000|0|0000>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.pins)
        XCTAssertEqual(result?.pins?.limits, [0, 0, 0])
        XCTAssertEqual(result?.pins?.probe, 0)
        XCTAssertEqual(result?.pins?.controls, [0, 0, 0, 0])
    }

    func testPinsLimitSwitchTripped() {
        // Y-axis limit tripped: Pn:010|0|0000
        let data = Data("<Hold|Pn:010|0|0000>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.pins)
        XCTAssertEqual(result?.pins?.limits, [0, 1, 0])
        XCTAssertEqual(result?.pins?.probe, 0)
        XCTAssertEqual(result?.pins?.controls, [0, 0, 0, 0])
    }

    func testPinsProbeTripped() {
        let data = Data("<Check|Pn:000|1|0000>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.pins)
        XCTAssertEqual(result?.pins?.limits, [0, 0, 0])
        XCTAssertEqual(result?.pins?.probe, 1)
        XCTAssertEqual(result?.pins?.controls, [0, 0, 0, 0])
    }

    func testPinsControlPins() {
        // Feed hold tripped: Pn:000|0|0100
        let data = Data("<Hold|Pn:000|0|0100>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.pins)
        XCTAssertEqual(result?.pins?.limits, [0, 0, 0])
        XCTAssertEqual(result?.pins?.probe, 0)
        XCTAssertEqual(result?.pins?.controls, [0, 1, 0, 0])
    }

    func testPinsAllSet() {
        let data = Data("<Alarm|Pn:111|1|1111>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.pins)
        XCTAssertEqual(result?.pins?.limits, [1, 1, 1])
        XCTAssertEqual(result?.pins?.probe, 1)
        XCTAssertEqual(result?.pins?.controls, [1, 1, 1, 1])
    }

    // MARK: - Combined fields

    func testFullReportWithAllFields() {
        let data = Data("<Run|MPos:100.5,50.25,-5.0|WPos:98.0,48.0,-5.0|FS:1000,8000|Bf:12|Pn:001|0|0000>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.state, "Run")
        XCTAssertEqual(result?.mPosX, 100.5, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosY, 50.25, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosZ, -5.0, accuracy: 1e-3)
        XCTAssertEqual(result?.wPosX, 98.0, accuracy: 1e-3)
        XCTAssertEqual(result?.wPosY, 48.0, accuracy: 1e-3)
        XCTAssertEqual(result?.wPosZ, -5.0, accuracy: 1e-3)
        XCTAssertEqual(result?.fs?.feed, 1000.0, accuracy: 1e-3)
        XCTAssertEqual(result?.fs?.spindle, 8000.0, accuracy: 1e-3)
        XCTAssertEqual(result?.buffer, 12)
        XCTAssertNotNil(result?.pins)
        XCTAssertEqual(result?.pins?.limits, [0, 0, 1])
        XCTAssertEqual(result?.pins?.probe, 0)
        XCTAssertEqual(result?.pins?.controls, [0, 0, 0, 0])
    }

    // MARK: - Missing optional fields

    func testMinimalReportStateOnly() {
        let data = Data("<Idle>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.state, "Idle")
        XCTAssertNil(result?.fs)
        XCTAssertNil(result?.buffer)
        XCTAssertNil(result?.pins)
        XCTAssertEqual(result?.mPosX, 0.0)
        XCTAssertEqual(result?.wPosX, 0.0)
    }

    func testStateAndMPosOnly() {
        let data = Data("<Run|MPos:1,2,3>\n".utf8)
        let result = StatusParser.parse(data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.state, "Run")
        XCTAssertEqual(result?.mPosX, 1.0, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosY, 2.0, accuracy: 1e-3)
        XCTAssertEqual(result?.mPosZ, 3.0, accuracy: 1e-3)
        XCTAssertNil(result?.fs)
        XCTAssertNil(result?.buffer)
        XCTAssertNil(result?.pins)
    }

    // MARK: - Negative tests

    func testInvalidInputReturnsNil() {
        let data = Data("ok\n".utf8)
        let result = StatusParser.parse(data)
        XCTAssertNil(result, "Plain 'ok' should not parse as status report")
    }

    func testMalformedBracketReturnsNil() {
        let data = Data("Idle|MPos:0,0>\n".utf8)
        let result = StatusParser.parse(data)
        XCTAssertNil(result, "Missing opening bracket should return nil")
    }

    func testEmptyBracketReturnsNil() {
        let data = Data("<>\n".utf8)
        let result = StatusParser.parse(data)
        XCTAssertNotNil(result, "Empty brackets should still parse (state empty → nil)")
    }

    func testNonStatusLineReturnsNil() {
        let data = Data("error: axis travel exceeded\n".utf8)
        let result = StatusParser.parse(data)
        XCTAssertNil(result, "Error message should not parse as status report")
    }
}

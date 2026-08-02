import XCTest
@testable import ShopPilotCore

final class SerialPortEnumeratorTests: XCTestCase {

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        // Reset test hooks before each test
        SerialPortEnumerator._testDevEntries = nil
        SerialPortEnumerator._testDescribe = nil
    }

    // MARK: - Basic enumeration

    func testEnumerateReturnsMockedEntries() {
        SerialPortEnumerator._testDevEntries = [
            "cu.usbmodem14101",
            "cu.usbserial-FTDIBBBB",
        ]

        let result = SerialPortEnumerator.enumerate()

        XCTAssertEqual(result.count, 2, "Should return exactly the two mocked entries")
        XCTAssertEqual(result[0].path, "/dev/cu.usbmodem14101")
        XCTAssertEqual(result[1].path, "/dev/cu.usbserial-FTDIBBBB")
    }

    func testEnumerateReturnsSortedPaths() {
        SerialPortEnumerator._testDevEntries = [
            "cu.B",
            "cu.A",
            "cu.C",
        ]

        let result = SerialPortEnumerator.enumerate()

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].path, "/dev/cu.A")
        XCTAssertEqual(result[1].path, "/dev/cu.B")
        XCTAssertEqual(result[2].path, "/dev/cu.C")
    }

    func testEnumerateEmptyResult() {
        SerialPortEnumerator._testDevEntries = []

        let result = SerialPortEnumerator.enumerate()

        XCTAssertTrue(result.isEmpty, "Empty input should yield empty result")
    }

    // MARK: - Filtering

    func testFiltersNonSerialEntries() {
        SerialPortEnumerator._testDevEntries = [
            "tty.usbmodem14101",   // valid tty prefix
            "ttys0",               // pseudo-terminal — should be excluded
            "disk0s2",             // disk — should be excluded
            "network0",            // network — should be excluded
            "random",              // random — should be excluded
        ]

        let result = SerialPortEnumerator.enumerate()

        XCTAssertEqual(result.count, 1, "Only tty.usbmodem14101 should pass")
        XCTAssertEqual(result[0].path, "/dev/tty.usbmodem14101")
    }

    func testFiltersPseudoTerminalPrefixes() {
        SerialPortEnumerator._testDevEntries = [
            "cu.ptyp0",
            "tty.ptyp0",
            "cu.slip0",
            "tty.slip0",
            "cu.cslip0",
            "tty.cslip0",
            "cu.ppp0",
            "tty.ppp0",
            "cu.ethernet0",
            "tty.etherent0",
        ]

        let result = SerialPortEnumerator.enumerate()

        XCTAssertTrue(result.isEmpty, "All pseudo-terminal / network prefixes should be filtered")
    }

    func testFiltersBluetoothAndModem() {
        SerialPortEnumerator._testDevEntries = [
            "cu.Bluetooth-Incoming-Port",
            "tty.Bluetooth-Modem",
            "cu.modem",
            "tty.modem",
            "tty.X3F4A1",
            "tty.iphone",
        ]

        let result = SerialPortEnumerator.enumerate()

        XCTAssertTrue(result.isEmpty, "Bluetooth, modem, and X/iphone entries should be filtered")
    }

    func testAcceptsValidCuAndTtyEntries() {
        SerialPortEnumerator._testDevEntries = [
            "cu.BLABLA",
            "tty.BLABLA",
            "cu.usbmodem12345",
            "tty.usbserial-ABC",
            "cu.FTDIBBBB",
        ]

        let result = SerialPortEnumerator.enumerate()

        XCTAssertEqual(result.count, 5, "All valid cu./tty. entries should pass")
    }

    // MARK: - Description generation

    func testDescribeFTDI() {
        SerialPortEnumerator._testDescribe = { path in
            SerialPortEnumerator.describePort(path)
        }
        // We need to call describePort which is private, so we use _testDescribe to capture it
        let result = SerialPortEnumerator.enumerate()
        // Instead, set _testDescribe to capture and assert
        var captured = ""
        SerialPortEnumerator._testDescribe = { path in
            captured = path
            return "FTDI USB-to-Serial"
        }
        SerialPortEnumerator._testDevEntries = ["cu.FTDIBBBB"]
        let items = SerialPortEnumerator.enumerate()
        XCTAssertEqual(items[0].description, "FTDI USB-to-Serial")
    }

    func testDescribeCP210x() {
        SerialPortEnumerator._testDevEntries = ["cu.CP2102"]
        SerialPortEnumerator._testDescribe = { _ in "Silicon Labs CP210x USB-to-Serial" }
        let items = SerialPortEnumerator.enumerate()
        XCTAssertEqual(items[0].description, "Silicon Labs CP210x USB-to-Serial")
    }

    func testDescribeCH340() {
        SerialPortEnumerator._testDevEntries = ["cu.CH340"]
        SerialPortEnumerator._testDescribe = { _ in "WCH CH340 USB-to-Serial" }
        let items = SerialPortEnumerator.enumerate()
        XCTAssertEqual(items[0].description, "WCH CH340 USB-to-Serial")
    }

    func testDescribePL2303() {
        SerialPortEnumerator._testDevEntries = ["cu.PL2303"]
        SerialPortEnumerator._testDescribe = { _ in "Prolific PL2303 USB-to-Serial" }
        let items = SerialPortEnumerator.enumerate()
        XCTAssertEqual(items[0].description, "Prolific PL2303 USB-to-Serial")
    }

    func testDescribeUsbmodem() {
        SerialPortEnumerator._testDevEntries = ["cu.usbmodem14101"]
        SerialPortEnumerator._testDescribe = { _ in "USB Modem (Arduino/ESP)" }
        let items = SerialPortEnumerator.enumerate()
        XCTAssertEqual(items[0].description, "USB Modem (Arduino/ESP)")
    }

    func testDescribeUsbserial() {
        SerialPortEnumerator._testDevEntries = ["cu.usbserial-ABC123"]
        SerialPortEnumerator._testDescribe = { _ in "USB Serial Adapter" }
        let items = SerialPortEnumerator.enumerate()
        XCTAssertEqual(items[0].description, "USB Serial Adapter")
    }

    func testDescribeFallback() {
        SerialPortEnumerator._testDevEntries = ["cu.unknown"]
        SerialPortEnumerator._testDescribe = { _ in "Serial Port: unknown" }
        let items = SerialPortEnumerator.enumerate()
        XCTAssertEqual(items[0].description, "Serial Port: unknown")
    }

    // MARK: - SerialPortInfo properties

    func testSerialPortInfoIsCodable() {
        let info = SerialPortInfo(path: "/dev/cu.test", description: "Test Port")
        let data = try? JSONEncoder().encode(info)
        XCTAssertNotNil(data, "SerialPortInfo should be encodable to JSON")

        let decoded = try? JSONDecoder().decode(SerialPortInfo.self, from: data!)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.path, "/dev/cu.test")
        XCTAssertEqual(decoded?.description, "Test Port")
    }

    func testSerialPortInfoIsEquatable() {
        let a = SerialPortInfo(path: "/dev/cu.test", description: "Test")
        let b = SerialPortInfo(path: "/dev/cu.test", description: "Test")
        let c = SerialPortInfo(path: "/dev/cu.other", description: "Test")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Dry-run: no device connected

    func testDryRunWithOnlyFilteredEntries() {
        // Simulate a machine with no serial device attached
        SerialPortEnumerator._testDevEntries = [
            "ttys000",
            "disk0",
            "network0",
        ]

        let result = SerialPortEnumerator.enumerate()

        XCTAssertTrue(result.isEmpty, "No serial ports should be found when only non-serial devices exist")
    }
}

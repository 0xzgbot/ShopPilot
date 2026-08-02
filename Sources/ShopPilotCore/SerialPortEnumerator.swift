import Foundation

// MARK: - SerialPortInfo

/// Enriched serial port information returned by enumeration.
public struct SerialPortInfo: Codable, Equatable, Sendable {
    public let path: String
    public let description: String

    public init(path: String, description: String) {
        self.path = path
        self.description = description
    }
}

// MARK: - SerialPortEnumerator

/// Enumerates candidate serial ports on macOS and returns enriched
/// `SerialPortInfo` structs suitable for a UI picker.
///
/// This component is deliberately simple: it scans `/dev` for
/// `cu.*` and `tty.*` entries, filters out pseudo-terminals and
/// network devices, and appends a human-readable description.
///
/// Out of scope: IOKit property queries, open/read/write, edge-case
/// devices (modems, Bluetooth pan, etc. are filtered heuristically).
public final class SerialPortEnumerator {

    // MARK: - Public API

    /// Enumerate candidate serial ports on the local macOS machine.
    ///
    /// Returns a sorted list of `SerialPortInfo` with stable `path`
    /// identifiers and human-readable `description` strings.
    public static func enumerate() -> [SerialPortInfo] {
        let paths = scanDevDirectory()
        return paths.map { path in
            SerialPortInfo(
                path: path,
                description: describePort(path)
            )
        }.sorted { $0.path < $1.path }
    }

    // MARK: - Internal (overridable for testing)

    /// Hook for tests: return a custom set of /dev entries.
    /// Default is `nil` (live scan).
    public static var _testDevEntries: [String]? = nil

    /// Hook for tests: return a custom description for a path.
    /// Default is `nil` (live description logic).
    public static var _testDescribe: ((String) -> String)? = nil

    // MARK: - Private

    private static func scanDevDirectory() -> [String] {
        // Test override: return fake entries
        if let entries = _testDevEntries {
            return entries.filter { isValidSerialEntry($0) }
                .map { "/dev/\($0)" }
        }

        let fileManager = FileManager.default
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: "/dev")
            return contents
                .filter { isValidSerialEntry($0) }
                .sorted()
                .map { "/dev/\($0)" }
        } catch {
            Log.warning("Could not enumerate /dev: \(error.localizedDescription)")
            return []
        }
    }

    /// Return true if the /dev entry looks like a candidate serial port.
    private static func isValidSerialEntry(_ name: String) -> Bool {
        guard name.hasPrefix("cu.") || name.hasPrefix("tty.") else { return false }

        // Exclude pseudo-terminals and network devices
        guard !name.hasPrefix("ttys") else { return false }
        guard !name.hasPrefix("cu.ptyp") else { return false }
        guard !name.hasPrefix("tty.ptyp") else { return false }
        guard !name.hasPrefix("cu.slip") else { return false }
        guard !name.hasPrefix("tty.slip") else { return false }
        guard !name.hasPrefix("cu.cslip") else { return false }
        guard !name.hasPrefix("tty.cslip") else { return false }
        guard !name.hasPrefix("cu.ppp") else { return false }
        guard !name.hasPrefix("tty.ppp") else { return false }
        guard !name.hasPrefix("cu.ethernet") else { return false }
        guard !name.hasPrefix("tty.etherent") else { return false }

        // Exclude Bluetooth PAN / modem entries (unreliable for CNC)
        guard !name.hasPrefix("cu.Bluetooth") else { return false }
        guard !name.hasPrefix("tty.Bluetooth") else { return false }
        guard !name.hasPrefix("cu.modem") else { return false }
        guard !name.hasPrefix("tty.modem") else { return false }
        guard !name.hasPrefix("tty.X") else { return false }
        guard !name.hasPrefix("tty.iphone") else { return false }

        return true
    }

    private static func describePort(_ path: String) -> String {
        if let custom = _testDescribe {
            return custom(path)
        }

        let fileName = (path as NSString).lastPathComponent

        // Chipset-based hints (matches existing RealSerialTransport logic)
        if fileName.contains("FTDI") || fileName.contains("ftdi") {
            return "FTDI USB-to-Serial"
        } else if fileName.contains("CP210") || fileName.contains("cp210") {
            return "Silicon Labs CP210x USB-to-Serial"
        } else if fileName.contains("CH340") || fileName.contains("ch340") {
            return "WCH CH340 USB-to-Serial"
        } else if fileName.contains("PL2303") || fileName.contains("pl2303") {
            return "Prolific PL2303 USB-to-Serial"
        } else if fileName.hasPrefix("cu.usbmodem") || fileName.hasPrefix("tty.usbmodem") {
            return "USB Modem (Arduino/ESP)"
        } else if fileName.hasPrefix("cu.usbserial") || fileName.hasPrefix("tty.usbserial") {
            return "USB Serial Adapter"
        } else {
            return "Serial Port: \(fileName)"
        }
    }
}

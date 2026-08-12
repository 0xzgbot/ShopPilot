import Foundation
import Darwin

/// Pure, testable mapping from a requested baud rate to Darwin termios
/// settings (8N1). No hardware port required: `RealSerialTransport` applies
/// these at `open()` time, and `ShopPilotVerify1401b` asserts the mapping.
///
/// SPK-1401b — the baud rate from config must never be discarded; the
/// previous `configureSerial` ignored it and relied on the OS default.
public struct SerialTermiosSettings: Sendable, Equatable {

    /// The resolved baud rate in bits per second — equal to the requested
    /// rate when supported, otherwise the deterministic fallback.
    public let baudRate: Int

    /// Darwin termios speed constant (B9600 … B115200) for `baudRate`.
    /// Meaningless when `customBaud` is set (IOSSIOSPEED path).
    public let speedConstant: speed_t

    /// Non-nil when the requested baud has no termios speed constant but IS a
    /// supported custom rate (SPK-1401g): applied via the Darwin
    /// `IOSSIOSPEED` ioctl instead of a cfsetspeed constant. This is how GRBL
    /// boards that run at 250000 actually get 250000 — silently mapping to
    /// B9600 would be a lie.
    public let customBaud: Int?

    /// c_cflag bits that must be SET for an 8N1 frame: 8 data bits (CS8),
    /// receiver enabled (CREAD), modem lines ignored (CLOCAL).
    public static let cflag8N1Set: tcflag_t = tcflag_t(CS8 | CREAD | CLOCAL)

    /// c_cflag bits that must be CLEARED for an 8N1 frame: parity enable
    /// (PARENB), 2 stop bits (CSTOPB), and the character-size mask (CSIZE).
    public static let cflag8N1Clear: tcflag_t = tcflag_t(PARENB | CSTOPB | CSIZE)

    /// Supported baud rates and their Darwin termios speed_t constants.
    public static let supported: [(baud: Int, speed: speed_t)] = [
        (115200, speed_t(B115200)),
        (57600, speed_t(B57600)),
        (38400, speed_t(B38400)),
        (19200, speed_t(B19200)),
        (9600, speed_t(B9600)),
    ]

    /// Custom baud rates with no termios constant, applied via the Darwin
    /// IOSSIOSPEED ioctl. 250000 is the common GRBL/FluidNC "fast USB"
    /// rate — the UI already offers it, so the transport must honor it.
    public static let customSupported: Set<Int> = [250_000]

    /// Deterministic fallback for unsupported baud rates — 9600, the most
    /// widely compatible GRBL/FluidNC default.
    public static let fallbackBaud: Int = 9600

    /// Map a requested baud rate to termios 8N1 settings.
    /// Unsupported rates resolve deterministically to the fallback.
    public static func make(baud: Int) -> SerialTermiosSettings {
        if let match = supported.first(where: { $0.baud == baud }) {
            return SerialTermiosSettings(baudRate: match.baud,
                                         speedConstant: match.speed,
                                         customBaud: nil)
        }
        if customSupported.contains(baud) {
            // SPK-1401g — a real custom rate: the speed constant field is
            // unused; the transport applies IOSSIOSPEED with `baud`.
            return SerialTermiosSettings(baudRate: baud,
                                         speedConstant: 0,
                                         customBaud: baud)
        }
        return SerialTermiosSettings(baudRate: fallbackBaud,
                                     speedConstant: speed_t(B9600),
                                     customBaud: nil)
    }

    /// Apply this settings' 8N1 frame + baud to a Darwin termios struct in
    /// place. Pure — no file descriptor required, so the verify CLT can
    /// assert it without a hardware port. `RealSerialTransport.configureSerial`
    /// calls this between tcgetattr and tcsetattr once a port handle exists.
    public func apply8N1(to t: inout termios) {
        t.c_cflag &= ~SerialTermiosSettings.cflag8N1Clear
        t.c_cflag |= SerialTermiosSettings.cflag8N1Set
        if customBaud == nil {
            t.c_ispeed = speedConstant
            t.c_ospeed = speedConstant
        }
    }

    /// Apply a custom baud (no termios constant) to an open file descriptor
    /// via the Darwin IOSSIOSPEED ioctl. No-op when `customBaud` is nil (the
    /// cfsetspeed path handles those). `RealSerialTransport.configureSerial`
    /// calls this right after tcsetattr when the settings carry a custom rate.
    public func applyCustomBaud(to fileDescriptor: Int32) {
        guard let baud = customBaud else { return }
        var rate = baud
        _ = Darwin.ioctl(fileDescriptor, Self.iosSIOSpeedRequest, &rate)
    }

    /// The Darwin `IOSSIOSPEED` ioctl request: `_IOW('t', 2, speed_t)`.
    /// Not exported by the SDK headers, so we compute it from the standard
    /// ioctl encoding (IOC_IN | type<<8 | nr | size<<16) — the same value
    /// ORSSerialPort uses to set non-termios baud rates on macOS.
    private static let iosSIOSpeedRequest: UInt = {
        let iocIn: UInt = 0x8000_0000
        let typeByte = UInt(UnicodeScalar("t").value) << 8
        let number: UInt = 2
        let sizeBits = UInt(MemoryLayout<speed_t>.size) << 16
        return iocIn | typeByte | number | sizeBits
    }()
}

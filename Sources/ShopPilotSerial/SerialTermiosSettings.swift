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
    public let speedConstant: speed_t

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

    /// Deterministic fallback for unsupported baud rates — 9600, the most
    /// widely compatible GRBL/FluidNC default.
    public static let fallbackBaud: Int = 9600

    /// Map a requested baud rate to termios 8N1 settings.
    /// Unsupported rates resolve deterministically to the fallback.
    public static func make(baud: Int) -> SerialTermiosSettings {
        let match = supported.first { $0.baud == baud }
        let resolved = match ?? (fallbackBaud, speed_t(B9600))
        return SerialTermiosSettings(baudRate: resolved.baud, speedConstant: resolved.speed)
    }

    /// Apply this settings' 8N1 frame + baud to a Darwin termios struct in
    /// place. Pure — no file descriptor required, so the verify CLT can
    /// assert it without a hardware port. `RealSerialTransport.configureSerial`
    /// calls this between tcgetattr and tcsetattr once a port handle exists.
    public func apply8N1(to t: inout termios) {
        t.c_cflag &= ~SerialTermiosSettings.cflag8N1Clear
        t.c_cflag |= SerialTermiosSettings.cflag8N1Set
        t.c_ispeed = speedConstant
        t.c_ospeed = speedConstant
    }
}

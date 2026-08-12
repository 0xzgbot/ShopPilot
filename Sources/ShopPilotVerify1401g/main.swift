import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1401g verify (CLT executable, no XCTest).
// Proves the 250000 custom baud path:
//   1. 250000 is NOT silently mapped to the fallback (B9600) — it resolves
//      to a settings with baudRate == 250000 and customBaud == 250000.
//   2. Standard rates (115200…9600) still map to their termios constants
//      with customBaud == nil (the cfsetspeed path is untouched).
//   3. Truly unsupported junk still falls back deterministically to 9600.
//   4. apply8N1 does NOT write c_ispeed/c_ospeed for custom baud (the
//      IOSSIOSPEED ioctl owns the rate) but DOES for standard rates.
//   5. applyCustomBaud is a no-op when customBaud is nil (real serial path
//      calls it unconditionally after tcsetattr — must be safe).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // 1. 250000 resolves to itself via the custom path — never the fallback.
    let fast = SerialTermiosSettings.make(baud: 250_000)
    try expect(fast.baudRate == 250_000,
               "250000 baudRate preserved (got \(fast.baudRate))")
    try expect(fast.customBaud == 250_000,
               "250000 carries customBaud == 250000 (got \(String(describing: fast.customBaud)))")
    try expect(fast.baudRate != SerialTermiosSettings.fallbackBaud,
               "250000 must NOT resolve to fallbackBaud \(SerialTermiosSettings.fallbackBaud)")

    // 2. Standard rates unchanged: constant + nil customBaud.
    for (baud, speed) in [(115200, speed_t(B115200)), (57600, speed_t(B57600)),
                          (38400, speed_t(B38400)), (19200, speed_t(B19200)),
                          (9600, speed_t(B9600))] {
        let s = SerialTermiosSettings.make(baud: baud)
        try expect(s.baudRate == baud, "\(baud) baudRate preserved")
        try expect(s.speedConstant == speed, "\(baud) maps to its speed constant")
        try expect(s.customBaud == nil, "\(baud) uses the cfsetspeed path (customBaud nil)")
    }

    // 3. Junk falls back deterministically.
    let junk = SerialTermiosSettings.make(baud: 123_456)
    try expect(junk.baudRate == SerialTermiosSettings.fallbackBaud,
               "123456 falls back to \(SerialTermiosSettings.fallbackBaud)")
    try expect(junk.customBaud == nil, "junk baud has no customBaud")

    // 4. apply8N1 speed-constant semantics.
    var t = termios()
    SerialTermiosSettings.make(baud: 115_200).apply8N1(to: &t)
    try expect(t.c_ispeed == speed_t(B115200) && t.c_ospeed == speed_t(B115200),
               "standard baud: apply8N1 sets c_ispeed/c_ospeed")
    var t2 = termios()
    SerialTermiosSettings.make(baud: 250_000).apply8N1(to: &t2)
    try expect(t2.c_ispeed == 0 && t2.c_ospeed == 0,
               "custom baud: apply8N1 leaves speeds zero (IOSSIOSPEED owns them)")

    // 5. applyCustomBaud no-op for standard rates (would be called with any
    //    fd after tcsetattr; must not crash or touch the fd).
    SerialTermiosSettings.make(baud: 115_200).applyCustomBaud(to: -1)

    print("1401g: PASS — 250000 baud applied")
}

do {
    try main()
} catch {
    print("1401g: FAIL — \(error)")
    exit(1)
}

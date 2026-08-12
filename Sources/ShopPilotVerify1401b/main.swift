import Foundation
import Darwin
import ShopPilotCore
import ShopPilotSerial

// SPK-1401b verify (CLT machine, no XCTest).
// Proves the termios baud path:
//   1. MAPPING: supported baud rates (115200/57600/38400/19200/9600) map to
//      the right Darwin speed_t constants (B115200/B57600/B38400/B19200/B9600);
//      unsupported rates (0, negative, 12345) fall back deterministically to
//      B9600 (SerialTermiosSettings.fallbackBaud).
//   2. 8N1 APPLY: SerialTermiosSettings.apply8N1(to:) is a pure function on a
//      real Darwin termios struct — asserted here WITHOUT any hardware port.
//      RealSerialTransport.configureSerial calls the same transformation at
//      open() time between tcgetattr and tcsetattr on the port's FileHandle
//      file descriptor — see Sources/ShopPilotSerial/RealSerialTransport.swift
//      (configureSerial: cfmakeraw(&t) → settings.apply8N1(to: &t) →
//      tcsetattr(fd, TCSANOW, &t)). The baud rate from config is applied, not
//      discarded.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Supported bauds map to the right speed_t constants. ────────────
    let cases: [(requested: Int, expected: speed_t)] = [
        (115200, speed_t(B115200)),
        (57600, speed_t(B57600)),
        (38400, speed_t(B38400)),
        (19200, speed_t(B19200)),
        (9600, speed_t(B9600)),
    ]
    for c in cases {
        let s = SerialTermiosSettings.make(baud: c.requested)
        try expect(s.speedConstant == c.expected,
                   "\(c.requested) baud → wrong speed constant")
        try expect(s.baudRate == c.requested,
                   "\(c.requested) baud → resolved baud should be the requested one")
    }

    // All supported constants must be distinct (mapping is not degenerate).
    let constants = Set(SerialTermiosSettings.supported.map { $0.speed })
    try expect(constants.count == SerialTermiosSettings.supported.count,
               "supported speed constants must be distinct")

    // ── 2. Unsupported bauds fall back deterministically. ─────────────────
    let fallback = SerialTermiosSettings.make(baud: 12345)
    try expect(fallback.speedConstant == speed_t(B9600),
               "unsupported baud (12345) must fall back to B9600")
    try expect(fallback.baudRate == SerialTermiosSettings.fallbackBaud,
               "fallback resolves to the declared fallbackBaud (9600)")
    try expect(SerialTermiosSettings.make(baud: 0).speedConstant == speed_t(B9600),
               "0 baud falls back to B9600")
    try expect(SerialTermiosSettings.make(baud: -1).speedConstant == speed_t(B9600),
               "negative baud falls back to B9600")
    try expect(SerialTermiosSettings.make(baud: 12345) == SerialTermiosSettings.make(baud: 12345),
               "fallback is deterministic (same settings every call)")
    try expect(SerialTermiosSettings.make(baud: 12345) == SerialTermiosSettings.make(baud: 9600),
               "unsupported baud resolves to exactly the 9600 settings")

    // ── 3. 8N1 application — pure, asserted without a hardware port. ──────
    // Seed adversarial flags + a wrong speed so a no-op apply would fail:
    // parity, 2 stop bits, and the CSIZE mask all set; speed at B9600.
    var t = termios()
    t.c_cflag = SerialTermiosSettings.cflag8N1Clear | SerialTermiosSettings.cflag8N1Set
    t.c_ispeed = speed_t(B9600)
    t.c_ospeed = speed_t(B9600)

    SerialTermiosSettings.make(baud: 115200).apply8N1(to: &t)

    try expect(t.c_cflag & SerialTermiosSettings.cflag8N1Set == SerialTermiosSettings.cflag8N1Set,
               "8N1 set flags present after apply (CS8|CREAD|CLOCAL)")
    // CS8's bits live INSIDE the CSIZE mask (both 0x30), so "clear mask is
    // zero" can never hold after setting CS8. Assert the decomposed
    // invariants instead: parity + 2-stop-bits gone, char-size field = CS8.
    try expect(t.c_cflag & tcflag_t(PARENB | CSTOPB) == 0,
               "parity enable and 2-stop-bit flags cleared after apply")
    try expect(t.c_cflag & tcflag_t(CSIZE) == tcflag_t(CS8),
               "character-size field set to 8 bits (CS8)")
    try expect(t.c_cflag == SerialTermiosSettings.cflag8N1Set,
               "c_cflag is exactly CS8|CREAD|CLOCAL after apply")
    try expect(t.c_ospeed == speed_t(B115200) && t.c_ispeed == speed_t(B115200),
               "both output and input speed set to the requested 115200 baud")
    try expect(t.c_ispeed == t.c_ospeed, "input and output speeds match")

    var tLow = termios()
    tLow.c_cflag = SerialTermiosSettings.cflag8N1Clear | SerialTermiosSettings.cflag8N1Set
    tLow.c_ispeed = speed_t(B115200)
    tLow.c_ospeed = speed_t(B115200)
    SerialTermiosSettings.make(baud: 9600).apply8N1(to: &tLow)
    try expect(tLow.c_ospeed == speed_t(B9600) && tLow.c_ispeed == speed_t(B9600),
               "9600 baud applied to both speeds")
    try expect(tLow.c_cflag & tcflag_t(PARENB | CSTOPB) == 0,
               "parity and 2-stop-bit flags cleared at 9600 too")
    try expect(tLow.c_cflag & tcflag_t(CSIZE) == tcflag_t(CS8),
               "character-size field is CS8 at 9600 too")

    print("1401b: PASS — termios baud applied")
}

do {
    try main()
} catch {
    print("1401b: FAIL — \(error)")
    exit(1)
}

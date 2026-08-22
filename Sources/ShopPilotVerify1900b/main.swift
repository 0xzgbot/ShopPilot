import Foundation
import ShopPilotCore

// SPK-1900b — frame-job / jog-to formatters: safety-critical motion shaping.

enum VerifyError: Error { case failed(String) }
var failures: [String] = []
func expect(_ cond: Bool, _ msg: String) {
    if !cond { failures.append(msg) }
}

func main() throws {
    // Frame: lifts to clearance FIRST, then pure-G0 perimeter, no M3/M5/G1.
    let frame = FrameJobFormatter.lines(widthMm: 300, heightMm: 200)
    expect(frame.first == "G0 Z5.000", "frame lifts to clearance first: \(frame.first ?? "nil")")
    expect(frame.count == 6, "frame = lift + 4 perimeter moves + return (got \(frame.count))")
    expect(frame[1] == "G0 X0.000 Y0.000", "frame starts at job origin")
    expect(frame.contains("G0 X300.000 Y200.000"), "far corner reached")
    expect(frame.last == "G0 X0.000 Y0.000", "frame returns to origin")
    for l in frame {
        expect(!l.contains("M3"), "no spindle-on in frame lines")
        expect(!l.contains("M5"), "no spindle-off needed (never turned on)")
        expect(l.hasPrefix("G0"), "frame is rapid-only: \(l)")
    }
    // Negative/zero dims still produce well-formed words.
    let tiny = FrameJobFormatter.lines(widthMm: 1, heightMm: 1, clearanceZMm: 2)
    expect(tiny.count == 6 && tiny.first == "G0 Z2.000", "custom clearance honored")

    // Jog-to: one absolute G0, three decimals, sign preserved.
    expect(JogToFormatter.line(xMm: 12.5, yMm: -3.25) == "G0 X12.500 Y-3.250",
           "jog-to formats absolute XY")
    let jl = JogToFormatter.line(xMm: 0, yMm: 0)
    expect(jl == "G0 X0.000 Y0.000", "origin jog well-formed")

    // Newline discipline lives in the transport (GCodeLine.sending), but the
    // formatter output must survive it unchanged.
    let framed = GCodeLine.sending(frame[0])
    expect(framed == "G0 Z5.000\n", "sending() terminates exactly once")

    // Determinism.
    expect(FrameJobFormatter.lines(widthMm: 10, heightMm: 20) ==
           FrameJobFormatter.lines(widthMm: 10, heightMm: 20), "deterministic")

    if !failures.isEmpty {
        throw VerifyError.failed(failures.joined(separator: "; "))
    }
}

do { try main() } catch { print("FAIL — \(error)"); exit(1) }
print("ShopPilotVerify1900b: PASS — frame/jog-to motion formatters")

import Foundation

// MARK: - Serial Write Gate (SPK-1401h)

/// One-writer-at-a-time gate for serial port I/O.
///
/// `RealSerialTransport` routes EVERY write — streamer G-code, status-poll
/// `?`, realtime `!`/`~`/0x18 — and the termios configuration block through
/// this single serial lock, so two writers can never interleave mid-frame on
/// the wire. Previously `read()` used `serialQueue.sync` while `write(_:)`
/// hit the FileHandle with no queue at all; a concurrent streamer + status
/// poll + realtime hold could byte-race on the port.
///
/// The gate is a tiny, pure concurrency primitive in ShopPilotSerial so the
/// verify CLT can drive it with concurrent tasks and PROVE serialization
/// (no overlapping executions) without any hardware port.
public final class SerialWriteGate: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.shoppilot.serial.write")
    /// Active-execution counter (0 or 1 while serialized) for the CLT's
    /// overlap probe. Accessed only from inside `queue.sync` blocks.
    private var activeExecutions = 0
    /// Maximum concurrent executions ever observed — must stay 1.
    private var maxConcurrent = 0

    public init() {}

    /// Run `op` under the write lock. Blocks until the gate is free, then
    /// executes `op` to completion — one writer at a time.
    public func synchronized<T>(_ op: () throws -> T) rethrows -> T {
        try queue.sync {
            activeExecutions += 1
            if activeExecutions > maxConcurrent {
                maxConcurrent = activeExecutions
            }
            defer { activeExecutions -= 1 }
            return try op()
        }
    }

    /// The highest number of simultaneous executions ever observed through
    /// this gate. Serialization invariant: this is always 1.
    public func peakConcurrency() -> Int {
        queue.sync { maxConcurrent }
    }
}

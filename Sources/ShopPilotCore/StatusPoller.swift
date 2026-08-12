import Foundation

// MARK: - StatusPoller

/// Polls a connected GRBL-class controller for its status by writing the
/// realtime status-query byte `?` to the transport on a fixed interval
/// (SPK-1401f).
///
/// GRBL does not push status reports on its own — the host must ask for them.
/// While a session is connected this poller keeps the machine answering
/// `<Idle|MPos:…|…>` reports, which the session's event reader parses into the
/// published position/state the UI shows.
///
/// The loop is intentionally small and safe:
/// - It writes `?` immediately, then every `intervalNanoseconds` while the
///   owning task keeps running.
/// - It is cancellable: cancellation surfaces through `Task.sleep` (throws)
///   and the top-of-loop `Task.isCancelled` check, so the loop ends cleanly
///   between writes.
/// - It is disconnected-safe: a failed write (transport closed / connection
///   lost) stops the loop permanently — it never retries, so no bytes are
///   written once the transport is gone.
public struct StatusPoller {

    /// The GRBL realtime status-query byte (`?`, 0x3F).
    public static let statusQueryByte: UInt8 = 0x3F

    /// Interval between status queries, in nanoseconds.
    public let intervalNanoseconds: UInt64

    public init(intervalNanoseconds: UInt64 = 500_000_000) {
        self.intervalNanoseconds = intervalNanoseconds
    }

    /// Run the poll loop until the calling task is cancelled or the transport
    /// rejects a write. Writes `?` immediately on entry, then on each tick.
    public func run(transport: MachineTransport) async {
        // Guard against a zero/absurd interval turning the loop into a
        // busy-write spin — never poll faster than 1 ms.
        let interval = max(intervalNanoseconds, 1_000_000)

        while !Task.isCancelled {
            do {
                try await transport.write(Data([Self.statusQueryByte]))
            } catch {
                // Transport rejected the write (closed / disconnected):
                // stop polling. Never retry after a failure.
                return
            }
            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                // Cancelled — end the loop cleanly between writes.
                return
            }
        }
    }
}

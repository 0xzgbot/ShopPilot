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

    /// SPK-1508 — when set and returning true, the poller goes quiet instead
    /// of writing `?`. The ok-wait streamer and the status poller share the
    /// wire; polling mid-stream would interleave `?` with the streamer's
    /// command/ok exchange. The session wires this to its attached
    /// streamer's `.streaming` state, so polling pauses for the stream
    /// duration and resumes on complete/cancel — while staying live on
    /// Idle/Hold (not streaming).
    private let isStreaming: (() -> Bool)?

    public init(intervalNanoseconds: UInt64 = 500_000_000,
                isStreaming: (() -> Bool)? = nil) {
        self.intervalNanoseconds = intervalNanoseconds
        self.isStreaming = isStreaming
    }

    /// Run the poll loop until the calling task is cancelled or the transport
    /// rejects a write. Writes `?` immediately on entry, then on each tick —
    /// unless the streaming gate says the streamer is mid-stream (SPK-1508).
    public func run(transport: MachineTransport) async {
        // Guard against a zero/absurd interval turning the loop into a
        // busy-write spin — never poll faster than 1 ms.
        let interval = max(intervalNanoseconds, 1_000_000)

        while !Task.isCancelled {
            // SPK-1508 — quiet while streaming: sleep through the tick and
            // re-check, so the streamer owns the wire for its whole run and
            // polling resumes the moment the stream ends.
            if isStreaming?() == true {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
                continue
            }
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

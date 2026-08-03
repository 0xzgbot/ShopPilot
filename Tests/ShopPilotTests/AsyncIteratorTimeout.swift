import Foundation

/// Test-only helper: `next(timeout:)` on async iterators.
///
/// The tests were written against a `next(timeout:)` API that does not exist on
/// `AsyncStream.Iterator`. This extension provides the same behaviour — wait for
/// the next element, or fail fast after `timeout` seconds so a missing event
/// cannot hang the test suite forever.
extension AsyncIteratorProtocol {
    func next(timeout: TimeInterval) async throws -> Element? {
        try await withThrowingTaskGroup(of: Element?.self) { group in
            var iterator = self
            group.addTask { try await iterator.next() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw CancellationError()
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }
}

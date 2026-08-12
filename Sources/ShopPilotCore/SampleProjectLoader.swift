import Foundation

// MARK: - Sample loading (SPK-1403a)

/// The slice of the app session the sample loader needs. Declared in Core so
/// the CLI verify can drive the full load lifecycle with a lightweight fake
/// (no app target import), and `AppSession` conforms with its real hooks.
///
/// `@preconcurrency`: the conforming session is `@MainActor` (its witness
/// methods touch main-actor-isolated state) while the loader is synchronous
/// and called from the main thread; the annotation silences the
/// conformance-isolation warning without hiding a real race.
@preconcurrency
public protocol SampleLoadingSession: AnyObject {
    /// The current document's file URL — set to nil when a sample becomes the
    /// active document (a sample is a fresh in-memory project, never the
    /// previously saved file).
    var packageURL: URL? { get set }
    /// Replace the session's live document with a loaded payload (the same
    /// path the package open uses).
    func applyPackagePayload(_ payload: ShopPilotPackagePayload)
    /// Clear the dirty flag (a fresh sample is not "unsaved changes").
    func markClean()
    /// Clear the undo stack (the previous document's history is gone).
    func clearUndoStack()
    /// Publish a user-facing status line.
    func setStatusMessage(_ message: String)
}

/// Owns the sample-project load lifecycle: stable id → bundled payload →
/// session mutation (apply + clean + undo-reset + status). Extracted from
/// `AppSession.loadSampleProject` (SPK-1403a slice 1) so the ~5000-line
/// facade shrinks and the lifecycle is CLT-verifiable without the app target.
/// No behavior change: identical hook sequence, identical status text.
public enum SampleProjectLoader {

    /// Load the bundled sample with `id` into `session`.
    /// Returns false (and mutates nothing) when the id is not a known sample.
    @discardableResult
    public static func load(id: UUID, into session: SampleLoadingSession) -> Bool {
        guard let payload = SampleProjectsStore.payload(for: id) else { return false }
        session.applyPackagePayload(payload)
        // Sample load is a fresh in-memory document: it must not look dirty,
        // must not inherit the previous file's URL (Save would overwrite the
        // old file), and must start a clean undo stack — mirroring
        // openPackage/NewJob.
        session.packageURL = nil
        session.markClean()
        session.clearUndoStack()
        session.setStatusMessage("Opened “\(payload.job.name)” — ready to design")
        return true
    }
}

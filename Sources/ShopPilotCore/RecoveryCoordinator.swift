import Foundation

// MARK: - Autosave session contract (SPK-1402a)

/// The slice of the app session the Autosaver needs. Declared in Core so
/// `AppSession` (app target) and CLI verify targets can both drive autosave
/// without importing the app target.
///
/// `@preconcurrency`: the conforming session is `@MainActor` (its witness
/// methods cross into main-actor-isolated code), while the Autosaver reads it
/// from its timer. The timer is scheduled on the main run loop, so the reads
/// happen on the main thread in practice; the annotation silences the
/// conformance-isolation warning without hiding a real race.
@preconcurrency
public protocol AutosaveSessionLike: AnyObject {
    /// The live document to autosave. Read fresh on every tick, so a job
    /// replaced by the session (open / sample / recipe) is saved as it is,
    /// not as it was when the Autosaver started.
    var autosaveJob: Job { get }
    /// Whether the session currently has unsaved changes.
    var isAutosaveDirty: Bool { get }
}

// MARK: - RecoveryCoordinator

/// The wiring `AppSession` calls to start the Autosaver and to decide whether
/// launch should offer "Recover unsaved work?". Kept in Core (not the app
/// target) so the CLI verify can assert start → recovery-write end to end.
public enum RecoveryCoordinator {

    /// The recovery artifact URL for a job: `<Autosave dir>/<job name>.shoppilot`.
    public static func recoveryURL(
        for job: Job,
        directory: URL = AutosaveRecovery.defaultDirectory()
    ) -> URL {
        let stem = job.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return directory.appendingPathComponent("\(stem.isEmpty ? "Untitled" : stem).shoppilot")
    }

    /// Start autosaving `session`'s document into the recovery directory and
    /// return the running Autosaver. The session is referenced weakly by the
    /// autosaver, so there is no retain cycle (the session owns the autosaver).
    @discardableResult
    public static func startAutosaver(
        for session: AutosaveSessionLike,
        directory: URL = AutosaveRecovery.defaultDirectory(),
        interval: TimeInterval = Autosaver.defaultInterval
    ) -> Autosaver {
        let autosaver = Autosaver(
            document: session.autosaveJob,
            saveURL: recoveryURL(for: session.autosaveJob, directory: directory),
            interval: interval,
            documentProvider: { [weak session] in session?.autosaveJob },
            isDocumentDirty: { [weak session] in session?.isAutosaveDirty ?? false }
        )
        autosaver.start()
        return autosaver
    }

    /// The newest recoverable snapshot, if any — what launch checks to offer
    /// "Recover unsaved work?".
    public static func latestSnapshot(
        directory: URL = AutosaveRecovery.defaultDirectory()
    ) -> RecoverySnapshot? {
        AutosaveRecovery.latest(in: AutosaveRecovery.scan(directory: directory))
    }
}

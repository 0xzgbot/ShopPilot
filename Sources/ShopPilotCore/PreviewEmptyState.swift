import Foundation

/// SPK-1103 — Preview empty-state model.
///
/// Pure logic (no UI) so the Preview stage's "nothing to show" copy is
/// CLT-verifiable: shown only when there is no G-code **and** no vectors.
public enum PreviewEmptyState {

    /// Headline shown in the Preview stage when there is nothing to preview.
    public static let title = "No toolpath yet"

    /// Guidance copy shown under the headline.
    public static let message = "Generate a profile from Design/Cut — or load a fixture in Machine — and the toolpath wireframe will appear here."

    /// True when the Preview stage has nothing to draw (no G-code, no vectors).
    public static func isEmpty(gcodeCount: Int, vectorCount: Int) -> Bool {
        gcodeCount == 0 && vectorCount == 0
    }

    /// Returns the empty-state copy when nothing is available, else nil.
    public static func copy(gcodeCount: Int, vectorCount: Int) -> (title: String, message: String)? {
        guard isEmpty(gcodeCount: gcodeCount, vectorCount: vectorCount) else { return nil }
        return (title, message)
    }
}

import Foundation

/// The six stage-rail stages, mirroring the app's `Stage` enum
/// (Sources/ShopPilot/StageEnum.swift). Kept in Core so CLT verifies and any
/// non-UI tooling can assert the friendly copy without importing the app target.
public enum FriendlyCopyStage: String, CaseIterable, Sendable {
    case setup
    case design
    case model
    case cut
    case preview
    case machine
}

/// Friendly, sentence-case stage intents for the stage rail and empty canvas.
///
/// The app's `Stage.intent` (Sources/ShopPilot/StageEnum.swift) delegates here,
/// so all user-facing stage copy lives in one place that CLT verifies can reach.
public enum FriendlyCopy {

    /// One-line statement of intent for a stage, shown under the stage title on
    /// the empty canvas and as the rail's tooltip. Sentence case, no jargon.
    public static func intent(for stage: FriendlyCopyStage) -> String {
        switch stage {
        case .setup:   return "Set up your board"
        case .design:  return "Draw it, or bring in a file"
        case .model:   return "Add 3D relief if you need it"
        case .cut:     return "Plan the cuts"
        case .preview: return "See the cut before you run it"
        case .machine: return "Connect, zero, and run"
        }
    }
}

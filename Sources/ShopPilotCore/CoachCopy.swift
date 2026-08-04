import Foundation

// MARK: - Coach copy (SPK-0318)

/// Plain-English coach copy for the Cut stage's follow-source state.
/// The Follow Source toggle itself shipped with SPK-0319; this is the coach
/// copy that explains the CONTRACT in both states:
///   - manual (link OFF): toolpaths are snapshots — art edits do NOT follow.
///   - autoFollow (link ON): art edits mark linked ops stale/dirty, and
///     recalculation is explicit — never silent.
public enum CoachCopy {

    public static func followSourceCutMessage(mode: FollowSourceMode, activeLinkCount: Int) -> String {
        switch mode {
        case .manual:
            return "Toolpaths don't follow art unless linked — select your vectors first, then apply the strategy. "
                + "With Follow Source off, editing your design does NOT update existing toolpaths: recalculate them to match the new art."
        case .autoFollow:
            let linkPart = activeLinkCount > 0
                ? "\(activeLinkCount) linked toolpath(s) go stale when you edit their art."
                : "Editing art marks linked toolpaths stale."
            return "Follow Source is ON — \(linkPart) A stale (dirty) toolpath blocks export until you recalculate. "
                + "Toolpaths never recalculate silently."
        }
    }
}

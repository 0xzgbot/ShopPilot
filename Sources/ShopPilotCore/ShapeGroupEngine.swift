import Foundation

// MARK: - ShapeGroupEngine (UI-polish cluster: Group / Ungroup)

/// Pure index-math for vector grouping. Lives in Core so a CLT can verify it
/// without the app target. The session owns the `[[Int]]` group list and
/// delegates all mutations here.
///
/// Semantics (match the reference "Group / Ungroup" behavior):
/// - A group is an ordered, de-duplicated list of shape indices.
/// - Grouping merges any groups that contain a selected index with the
///   selection itself, producing one group.
/// - Ungrouping removes group membership for the selected indices; a group
///   that loses all members disappears.
/// - Transforms (move/nudge/flip/rotate/scale) expand the selection to every
///   member of any group that touches it, so grouped vectors move together.
public enum ShapeGroupEngine {

    /// Merge the selected indices into the existing groups.
    /// Returns the new group list. Selected indices that were already in a
    /// group fold that group in; everything else becomes one new group.
    public static func grouping(
        selected: Set<Int>,
        existing: [[Int]],
        shapeCount: Int
    ) -> [[Int]] {
        let valid = selected.filter { $0 >= 0 && $0 < shapeCount }
        guard !valid.isEmpty else { return existing }

        var kept: [[Int]] = []
        var merged = Set(valid)
        for group in existing {
            let members = group.filter { $0 >= 0 && $0 < shapeCount }
            if members.contains(where: { valid.contains($0) }) {
                merged.formUnion(members)
            } else {
                kept.append(members)
            }
        }
        kept.append(merged.sorted())
        return kept
    }

    /// Remove the selected indices from every group. Groups that become empty
    /// are dropped. Returns the new group list.
    public static func ungrouping(
        selected: Set<Int>,
        existing: [[Int]]
    ) -> [[Int]] {
        guard !selected.isEmpty else { return existing }
        var result: [[Int]] = []
        for group in existing {
            let remaining = group.filter { !selected.contains($0) }
            if !remaining.isEmpty {
                result.append(remaining)
            }
        }
        return result
    }

    /// The selection expanded to whole groups: any group that touches the
    /// selection contributes all of its members.
    public static func expandedSelection(
        selected: Set<Int>,
        groups: [[Int]]
    ) -> Set<Int> {
        var result = selected
        for group in groups where !group.isEmpty {
            if group.contains(where: { selected.contains($0) }) {
                result.formUnion(group)
            }
        }
        return result
    }

    /// Drop indices that no longer exist (deletion / replace) from all groups.
    /// Groups that become empty are removed.
    public static func removing(
        indices: Set<Int>,
        from groups: [[Int]]
    ) -> [[Int]] {
        var result: [[Int]] = []
        for group in groups {
            let remaining = group.filter { !indices.contains($0) }
            if !remaining.isEmpty {
                result.append(remaining)
            }
        }
        return result
    }

    /// Persistable validation: clamp every index to `shapeCount`, drop
    /// out-of-range entries and empty groups (legacy-safe load).
    public static func sanitized(_ groups: [[Int]], shapeCount: Int) -> [[Int]] {
        groups.compactMap { group in
            let members = group.filter { $0 >= 0 && $0 < shapeCount }
            return members.isEmpty ? nil : members.sorted()
        }
    }
}

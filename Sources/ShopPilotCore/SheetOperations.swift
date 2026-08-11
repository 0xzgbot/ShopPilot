import Foundation

// MARK: - Sheet operations (SPK-1208)

/// Sheet duplication + toolpath transfer helpers. Duplication deep-copies a
/// sheet with NEW identities everywhere (sheet id, layer ids) so the copy is
/// an independent document surface; the toolpath move validates target
/// existence + self-move guards. Pure + testable; session wires the results
/// into the live Job/tree.
public enum SheetOperations {

    /// Deep-copy a sheet: new sheet + layer UUIDs, same dims/material/preset,
    /// same layer properties (visible/locked/name). The name gets a " copy"
    /// suffix unless one is given.
    public static func duplicate(
        _ sheet: Sheet,
        newName: String? = nil
    ) -> Sheet {
        let copiedLayers = sheet.layers.map { layer -> Layer in
            // Rebuild with a fresh id (Layer.id is `let`) but keep every
            // property the user set — dims, visibility, lock, vectors.
            return Layer(
                name: layer.name,
                isVisible: layer.isVisible,
                isLocked: layer.isLocked,
                vectors: layer.vectors,
                toolpathIds: []
            )
        }
        return Sheet(
            name: newName ?? (sheet.name + " copy"),
            width: sheet.width,
            depth: sheet.depth,
            height: sheet.height,
            layers: copiedLayers,
            isDoubleSided: sheet.isDoubleSided,
            stockPresetName: sheet.stockPresetName
        )
    }

    /// Validate a toolpath move to another sheet. Returns nil when the move
    /// is legal, or a human reason when it isn't.
    /// - Parameters:
    ///   - targetSheetID: the destination sheet.
    ///   - sheets: the job's current sheets (existence check).
    ///   - sourceSheetID: the sheet the toolpath currently belongs to (nil =
    ///     unknown → allowed, the toolpath gets homed to the target).
    public static func validateToolpathMove(
        targetSheetID: UUID,
        sheets: [Sheet],
        sourceSheetID: UUID? = nil
    ) -> String? {
        guard sheets.contains(where: { $0.id == targetSheetID }) else {
            return "Target sheet no longer exists"
        }
        if let sourceSheetID, sourceSheetID == targetSheetID {
            return "Toolpath already belongs to that sheet"
        }
        return nil
    }

    /// The display name for a sheet's toolpath group ("Sheet 1 Ops").
    public static func toolpathGroupName(for sheet: Sheet) -> String {
        "\(sheet.name) Ops"
    }
}

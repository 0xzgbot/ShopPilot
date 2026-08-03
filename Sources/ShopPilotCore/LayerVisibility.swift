import Foundation

// MARK: - Layer Visibility Filtering (SPK-1101h)

/// Pure helpers for layer-visibility filtering of design shapes.
///
/// The design canvas keeps a flat `shapes` array plus a parallel
/// `shapeLayerIDs` array (one layer UUID per shape). These helpers answer
/// "which shapes sit on a visible layer?" without touching UI state, so CLT
/// verify targets can prove the semantics and the session can share one
/// implementation.
public enum LayerVisibility {

    /// Whether the shape at `index` (parallel `shapeLayerIDs`) sits on a layer
    /// that is currently visible.
    ///
    /// - Shapes with no recorded assignment (back-compat with documents that
    ///   predate per-shape layer tracking) count as visible.
    /// - Shapes whose layer id no longer exists (orphaned) count as hidden.
    public static func isVisible(
        index: Int,
        shapeLayerIDs: [UUID],
        layers: [Layer]
    ) -> Bool {
        guard shapeLayerIDs.indices.contains(index) else { return true }
        let layerID = shapeLayerIDs[index]
        guard let layer = layers.first(where: { $0.id == layerID }) else { return false }
        return layer.isVisible
    }

    /// Indices of shapes (in `0..<count`, parallel to `shapeLayerIDs`) that sit
    /// on a visible layer. The design canvas draws only these.
    public static func visibleIndices(
        count: Int,
        shapeLayerIDs: [UUID],
        layers: [Layer]
    ) -> [Int] {
        (0..<count).filter {
            isVisible(index: $0, shapeLayerIDs: shapeLayerIDs, layers: layers)
        }
    }

    /// Rebuild every layer's `vectors` from a flat path list, matching by
    /// `VectorPath.layerId`. Layers with no matching paths end up empty
    /// (stale vectors are cleared).
    public static func distribute(_ paths: [VectorPath], into layers: inout [Layer]) {
        for index in layers.indices {
            let id = layers[index].id
            layers[index].vectors = paths.filter { $0.layerId == id }
        }
    }
}

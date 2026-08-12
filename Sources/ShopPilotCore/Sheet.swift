import Foundation

// MARK: - Sheet

/// A single work surface within a Job. Supports single-sided and double-sided jobs.
public struct Sheet: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var width: Double      // mm
    public var depth: Double      // mm (Y-axis)
    public var height: Double     // mm (Z-stock thickness)
    public var layers: [Layer]
    public var isDoubleSided: Bool
    
    /// Material this sheet is made from. Defaults to Pine if not set.
    public var material: Material?

    /// Name of the stock sheet preset this sheet was created from
    /// (e.g. `4'x8'x0.375''`), if any. Persisted so the Job Setup picker
    /// shows the applied preset after save/open. Nil = custom dimensions.
    public var stockPresetName: String?

    /// Z offset for the back side of a double-sided sheet.
    public var backSideZOffset: Double { -height }

    public init(
        id: UUID = UUID(),
        name: String = "Sheet 1",
        width: Double = 600,
        depth: Double = 400,
        height: Double = 25,
        layers: [Layer] = [],
        isDoubleSided: Bool = false,
        stockPresetName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.depth = depth
        self.height = height
        self.layers = layers
        self.isDoubleSided = isDoubleSided
        self.stockPresetName = stockPresetName
    }

    /// Add a layer to this sheet.
    public mutating func addLayer(_ layer: Layer) {
        layers.append(layer)
    }

    /// Remove a layer by ID.
    @discardableResult
    public mutating func removeLayer(id: UUID) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return false }
        layers.remove(at: index)
        return true
    }

    /// Convenience: first layer, or create one.
    public mutating func ensureSingleLayer() -> Layer {
        if let existing = layers.first {
            return existing
        }
        let newLayer = Layer(name: "Layer 1")
        addLayer(newLayer)
        return newLayer
    }

    /// Move a layer to a new index (0-based) within this sheet's layer list.
    /// Reorders the array; returns false if the index is out of range or a no-op.
    @discardableResult
    public mutating func moveLayer(from sourceIndex: Int, to destinationIndex: Int) -> Bool {
        guard layers.indices.contains(sourceIndex) else { return false }
        let clamped = min(max(destinationIndex, 0), layers.count - 1)
        guard sourceIndex != clamped else { return false }
        let layer = layers.remove(at: sourceIndex)
        layers.insert(layer, at: clamped)
        return true
    }

    /// Total area in square mm.
    public var area: Double { width * depth }

    /// Center point of the sheet (for zeroing).
    public var center: (x: Double, y: Double) {
        (width / 2, depth / 2)
    }
}

// MARK: - Stock dimension display (SPK-1400g)

/// One stock axis of a sheet: which axis, its display label, and its mm value.
/// Shared by the Setup inspector (and the CLT verify) so the W/D/H labels and
/// formatting have a single source of truth and always describe the ACTIVE
/// sheet's real values — never a fake or first-sheet-only readout.
public struct StockDimension: Sendable, Equatable {
    public enum Axis: String, Sendable {
        case width
        case depth
        case height
    }

    public let axis: Axis
    public let label: String
    public let valueMm: Double

    /// Compact one-decimal mm string, e.g. "600.0".
    public var formatted: String { String(format: "%.1f", valueMm) }

    public init(axis: Axis, label: String, valueMm: Double) {
        self.axis = axis
        self.label = label
        self.valueMm = valueMm
    }
}

extension Sheet {
    /// The sheet's stock dimensions in inspector display order (width/depth/height).
    public var stockDimensions: [StockDimension] {
        [
            StockDimension(axis: .width, label: "Width", valueMm: width),
            StockDimension(axis: .depth, label: "Depth", valueMm: depth),
            StockDimension(axis: .height, label: "Height", valueMm: height),
        ]
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct Sheet_Previews: PreviewProvider {
    static var previews: some View {
        Text("Sheet preview requires Xcode Previews")
    }
}
#endif

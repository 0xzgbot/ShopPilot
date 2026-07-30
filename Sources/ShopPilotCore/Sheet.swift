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

    /// Z offset for the back side of a double-sided sheet.
    public var backSideZOffset: Double { -height }

    public init(
        id: UUID = UUID(),
        name: String = "Sheet 1",
        width: Double = 600,
        depth: Double = 400,
        height: Double = 25,
        layers: [Layer] = [],
        isDoubleSided: Bool = false
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.depth = depth
        self.height = height
        self.layers = layers
        self.isDoubleSided = isDoubleSided
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

    /// Total area in square mm.
    public var area: Double { width * depth }

    /// Center point of the sheet (for zeroing).
    public var center: (x: Double, y: Double) {
        (width / 2, depth / 2)
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

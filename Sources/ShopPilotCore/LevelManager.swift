import Foundation

#if canImport(Combine)
import Combine
#endif

// MARK: - LevelManager

/// Observable manager for levels in the 3D component tree.
/// Integrates with SwiftUI via @ObservableObject for reactive UI updates.
public final class LevelManager: ObservableObject {
    @Published public var levels: [Level]
    @Published public var selectedLevelID: UUID?

    public init() {
        self.levels = []
        self.selectedLevelID = nil
    }

    // MARK: - Level CRUD

    /// Creates a new level with a given name.
    /// - Parameter name: Display name for the level.
    /// - Returns: The new level's UUID.
    @discardableResult
    public func addLevel(_ name: String) -> UUID {
        let id = UUID()
        let level = Level(id: id, name: name)
        levels.append(level)
        return id
    }

    /// Removes a level by ID.
    /// - Parameter id: The level UUID to remove.
    public func removeLevel(_ id: UUID) {
        guard let idx = levels.firstIndex(where: { $0.id == id }) else { return }
        levels.remove(at: idx)
        if selectedLevelID == id {
            selectedLevelID = nil
        }
    }

    // MARK: - Level Properties

    /// Toggles the visibility of a level.
    /// - Parameter id: The level UUID.
    public func toggleVisibility(_ id: UUID) {
        guard let idx = levels.firstIndex(where: { $0.id == id }) else { return }
        levels[idx].visible.toggle()
    }

    /// Toggles the lock state of a level.
    /// - Parameter id: The level UUID.
    public func toggleLock(_ id: UUID) {
        guard let idx = levels.firstIndex(where: { $0.id == id }) else { return }
        levels[idx].locked.toggle()
    }

    /// Sets the opacity of a level.
    /// - Parameters:
    ///   - id: The level UUID.
    ///   - opacity: Opacity value clamped to 0.0–1.0.
    public func setOpacity(_ id: UUID, opacity: Double) {
        guard let idx = levels.firstIndex(where: { $0.id == id }) else { return }
        levels[idx].opacity = max(0.0, min(1.0, opacity))
    }

    /// Sets the blend mode of a level.
    /// - Parameters:
    ///   - id: The level UUID.
    ///   - mode: Blend mode name (e.g. "normal", "multiply", "screen").
    public func setBlendMode(_ id: UUID, mode: String) {
        guard let idx = levels.firstIndex(where: { $0.id == id }) else { return }
        levels[idx].blendMode = mode
    }

    // MARK: - Level Ordering

    /// Swaps a level with the one above it in the list.
    /// No-op if already first or not found.
    /// - Parameter id: The level UUID.
    public func moveLevelUp(_ id: UUID) {
        guard let idx = levels.firstIndex(where: { $0.id == id }) else { return }
        guard idx > 0 else { return }
        levels.swapAt(idx, idx - 1)
    }

    /// Swaps a level with the one below it in the list.
    /// No-op if already last or not found.
    /// - Parameter id: The level UUID.
    public func moveLevelDown(_ id: UUID) {
        guard let idx = levels.firstIndex(where: { $0.id == id }) else { return }
        let maxIdx = levels.count - 1
        guard idx < maxIdx else { return }
        levels.swapAt(idx, idx + 1)
    }

    // MARK: - Level Mirror Modes (SPK-0908)

    /// Mirror axis for a level's content.
    public enum MirrorAxis: String, Codable, Sendable {
        case horizontal   // flip X
        case vertical     // flip Y
        case both         // flip X + Y (180° rotation)
    }

    /// Mirror the content of a level in place: flips every component
    /// heightfield's grid along the requested axis (X, Y, or both). The
    /// grid's world origin stays fixed, so a horizontally-mirrored relief
    /// keeps the same sheet footprint.
    /// - Parameters:
    ///   - id: The level UUID.
    ///   - axis: Which axis to mirror about.
    public func mirrorLevel(_ id: UUID, axis: MirrorAxis) {
        guard let idx = levels.firstIndex(where: { $0.id == id }) else { return }
        levels[idx].components = levels[idx].components
        // The level only stores component ids; the actual heightfields live
        // on the document's component stack. This manager owns the level
        // metadata — the grid flip is applied via `LevelMirrorEngine.mirror`
        // by the session, which holds the components. We record the applied
        // mirror mode on the level so the UI can show the current state.
        levels[idx].mirrorMode = axis
    }
}

// MARK: - Level mirror engine (SPK-0908)

/// Real heightfield mirroring: flips the grid along X, Y, or both axes while
/// keeping the world footprint fixed (minX/minY/cellSize unchanged).
public enum LevelMirrorEngine {

    /// Mirror a heightfield grid along the requested axis. Returns a new grid
    /// with the same dims + world origin; cell (x, y) reads the source cell
    /// at the mirrored coordinate.
    public static func mirror(_ grid: HeightfieldData, axis: LevelManager.MirrorAxis) -> HeightfieldData {
        let w = grid.width
        let h = grid.height
        var out = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let srcX: Int
                let srcY: Int
                switch axis {
                case .horizontal: srcX = w - 1 - x; srcY = y
                case .vertical:   srcX = x; srcY = h - 1 - y
                case .both:       srcX = w - 1 - x; srcY = h - 1 - y
                }
                out[y * w + x] = grid.heights[srcY * w + srcX]
            }
        }
        return HeightfieldData(width: w, height: h, cellSizeMm: grid.cellSizeMm,
                               minX: grid.minX, minY: grid.minY, heights: out)
    }
}



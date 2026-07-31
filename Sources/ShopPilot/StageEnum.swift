import SwiftUI
import ShopPilotCore

/// Type-safe stage management for the ShopPilot stage rail.
/// Each case maps to a human-readable label and an SF Symbol icon name.
enum Stage: String, CaseIterable, Identifiable {
    case setup
    case design
    case model
    case cut
    case preview
    case machine

    // MARK: - Identifiable

    var id: String { rawValue }

    // MARK: - Display properties

    /// Human-readable label shown on the stage button.
    var title: String {
        switch self {
        case .setup:      return "Setup"
        case .design:     return "Design"
        case .model:      return "Model"
        case .cut:        return "Cut"
        case .preview:    return "Preview"
        case .machine:    return "Machine"
        }
    }

    /// SF Symbol system icon for the stage button.
    var icon: String {
        switch self {
        case .setup:      return "gearshape"
        case .design:     return "pen.toolpath"
        case .model:      return "cube.box"
        case .cut:        return "scissors"
        case .preview:    return "play.circle"
        case .machine:    return "printer.tray"
        }
    }
    
    /// Whether this stage is available for the given tier.
    /// The Model stage requires Studio3D tier; Core/Studio show it as locked.
    public func isAvailable(tier: ProductTier) -> Bool {
        switch self {
        case .model:
            return tier.has3D
        default:
            return true
        }
    }
    
    /// Human-readable label for the locked state.
    public var lockedLabel: String? {
        switch self {
        case .model:
            return "Requires Studio3D"
        default:
            return nil
        }
    }

    // MARK: - Initializers

    /// Creates a Stage from a raw string value (case-insensitive).
    init?(from string: String) {
        guard let stage = Self.allCases.first(where: { $0.rawValue.lowercased() == string.lowercased() }) else {
            return nil
        }
        self = stage
    }

    /// Convenience: create from a raw string (already provided by RawRepresentable).
    init?(rawValueString: String) {
        self.init(rawValue: rawValueString)
    }
}

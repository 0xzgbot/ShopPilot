import Foundation

// MARK: - Dynamic Height/Tilt/Fade

/// Represents a dynamic height modification applied to a 3D component.
/// Used for shaping surfaces with height maps, tilt angles, and fade profiles.
public struct DynamicHeightModifier: Identifiable, Codable, Sendable {
    public let id: UUID
    
    /// The component this modifier applies to
    public var componentID: UUID
    
    /// Modifier type
    public var type: ModifierType
    
    /// Height scale factor (0.0 = flat, 1.0 = full height)
    public var heightScale: Double
    
    /// Tilt angle in degrees
    public var tiltAngle: Double
    
    /// Fade profile (0.0 = no fade, 1.0 = full fade)
    public var fadeAmount: Double
    
    /// Fade direction
    public var fadeDirection: FadeDirection
    
    /// Active modifier
    public var active: Bool
    
    /// Custom height function (if type is .custom)
    public var customFunction: String?
    
    public init(
        id: UUID = UUID(),
        componentID: UUID,
        type: ModifierType = .height,
        heightScale: Double = 1.0,
        tiltAngle: Double = 0.0,
        fadeAmount: Double = 0.0,
        fadeDirection: FadeDirection = .none,
        active: Bool = true,
        customFunction: String? = nil
    ) {
        self.id = id
        self.componentID = componentID
        self.type = type
        self.heightScale = max(0.0, min(1.0, heightScale))
        self.tiltAngle = tiltAngle
        self.fadeAmount = max(0.0, min(1.0, fadeAmount))
        self.fadeDirection = fadeDirection
        self.active = active
        self.customFunction = customFunction
    }
}

/// The type of dynamic modifier
public enum ModifierType: String, Codable, Sendable {
    case height
    case tilt
    case fade
    case custom
}

/// Fade direction for dynamic modifiers
public enum FadeDirection: String, Codable, Sendable {
    case none
    case leftToRight
    case rightToLeft
    case topToBottom
    case bottomToTop
    case centerOut
    case radial
}

// MARK: - DynamicHeightManager

/// Manages dynamic height/tilt/fade modifiers for 3D components.
public final class DynamicHeightManager: ObservableObject {
    @Published public var modifiers: [DynamicHeightModifier]
    @Published public var activeModifierID: UUID?
    
    public init() {
        self.modifiers = []
        self.activeModifierID = nil
    }
    
    /// Adds a new dynamic modifier to a component.
    @discardableResult
    public func addModifier(
        for componentID: UUID,
        type: ModifierType = .height,
        heightScale: Double = 1.0,
        tiltAngle: Double = 0.0,
        fadeAmount: Double = 0.0,
        fadeDirection: FadeDirection = .none
    ) -> UUID {
        let id = UUID()
        let modifier = DynamicHeightModifier(
            id: id,
            componentID: componentID,
            type: type,
            heightScale: heightScale,
            tiltAngle: tiltAngle,
            fadeAmount: fadeAmount,
            fadeDirection: fadeDirection
        )
        modifiers.append(modifier)
        return id
    }
    
    /// Removes a modifier by ID.
    public func removeModifier(_ id: UUID) {
        guard let idx = modifiers.firstIndex(where: { $0.id == id }) else { return }
        modifiers.remove(at: idx)
        if activeModifierID == id {
            activeModifierID = nil
        }
    }
    
    /// Sets the active modifier.
    public func setActive(_ id: UUID) {
        guard modifiers.contains(where: { $0.id == id }) else { return }
        activeModifierID = id
    }
    
    /// Gets the active modifier.
    public func getActiveModifier() -> DynamicHeightModifier? {
        guard let id = activeModifierID else { return nil }
        return modifiers.first(where: { $0.id == id })
    }
    
    /// Updates modifier properties.
    public func updateModifier(
        _ id: UUID,
        heightScale: Double? = nil,
        tiltAngle: Double? = nil,
        fadeAmount: Double? = nil,
        fadeDirection: FadeDirection? = nil
    ) {
        guard let idx = modifiers.firstIndex(where: { $0.id == id }) else { return }
        if let heightScale = heightScale {
            modifiers[idx].heightScale = max(0.0, min(1.0, heightScale))
        }
        if let tiltAngle = tiltAngle {
            modifiers[idx].tiltAngle = tiltAngle
        }
        if let fadeAmount = fadeAmount {
            modifiers[idx].fadeAmount = max(0.0, min(1.0, fadeAmount))
        }
        if let fadeDirection = fadeDirection {
            modifiers[idx].fadeDirection = fadeDirection
        }
    }
    
    /// Toggles the active state of a modifier.
    public func toggleActive(_ id: UUID) {
        guard let idx = modifiers.firstIndex(where: { $0.id == id }) else { return }
        modifiers[idx].active.toggle()
    }
    
    /// Gets all modifiers for a component.
    public func getModifiers(for componentID: UUID) -> [DynamicHeightModifier] {
        modifiers.filter { $0.componentID == componentID }
    }
    
    /// Clears all modifiers for a component.
    public func clearModifiers(for componentID: UUID) {
        modifiers.removeAll { $0.componentID == componentID }
    }
}

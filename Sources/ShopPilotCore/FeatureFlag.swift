import Foundation

// MARK: - Product Tier

/// ShopPilot product tier — determines which features are available.
/// Core = base free tier (2D design, profile/pocket/drill toolpaths, preview, GRBL control).
/// Studio = Core + text-on-curve, V-Carve, quick engrave, keep-out zones, templates, job sheets.
/// Studio3D = Studio + full 3D component model, combine modes, 3D toolpaths, sculpt.
public enum ProductTier: String, Sendable {
    case core
    case studio
    case studio3d
    
    /// Whether 3D features are available.
    public var has3D: Bool {
        switch self {
        case .core, .studio:
            return false
        case .studio3d:
            return true
        }
    }
    
    /// Whether Studio features are available.
    public var hasStudio: Bool {
        switch self {
        case .core:
            return false
        case .studio, .studio3d:
            return true
        }
    }
}

// MARK: - Feature Flag

/// Feature flags gate access to specific capabilities based on the active product tier.
/// All 3D features are gated behind `.has3D` so the Core tier ships without any 3D code path.
public enum FeatureFlag: Sendable {
    
    // MARK: - 3D Features (Studio3D only)
    
    /// Model stage: 3D relief components, shape tools, sculpt mode.
    case modelStage3D
    
    /// 3D toolpath strategies (rough/finish).
    case toolpath3D
    
    /// Component browser and combine modes (add/subtract/merge/low).
    case componentBrowser
    
    /// STL/OBJ import for 3D relief models.
    case import3D
    
    /// Sculpt mode UI and engine.
    case sculptMode
    
    // MARK: - Studio Features (Studio+ only)
    
    /// Text-on-curve strategy.
    case textOnCurve
    
    /// Quick engrave strategy.
    case quickEngrave
    
    /// Toolpath templates save/load.
    case toolpathTemplates
    
    /// Job sheet PDF export.
    case jobSheetPDF
    
    /// Keep-out zones v0.
    case keepOutZones
    
    // MARK: - Core Features (always available)
    
    /// 2D vector design tools (line, arc, circle, rect, etc.).
    case vectorDesign2D
    
    /// Profile/pocket/drill toolpaths.
    case coreToolpaths
    
    /// Preview simulation.
    case previewSimulation
    
    /// GRBL machine control.
    case machineControl
    
    // MARK: - Evaluation
    
    /// Check if a feature is available for the given tier.
    public static func isAvailable(_ feature: FeatureFlag, tier: ProductTier) -> Bool {
        switch feature {
        // 3D features: Studio3D only
        case .modelStage3D, .toolpath3D, .componentBrowser, .import3D, .sculptMode:
            return tier.has3D
        // Studio features: Studio+ only
        case .textOnCurve, .quickEngrave, .toolpathTemplates, .jobSheetPDF, .keepOutZones:
            return tier.hasStudio
        // Core features: always available
        case .vectorDesign2D, .coreToolpaths, .previewSimulation, .machineControl:
            return true
        }
    }
}

import Foundation

/// StageGate gates stage availability based on product tier.
/// Core tier: Setup, Design, Cut, Preview, Machine (5 stages)
/// Studio tier: Same 5 + Model (but Model shows upgrade prompt)
/// Studio3D tier: Full Model with 3D features
public enum StageGate {
    
    /// Whether the Model stage is accessible.
    /// Core tier: Model is present but shows upgrade prompt.
    /// Studio3D: Model is fully functional.
    public static func canUseModelStage(tier: ProductTier) -> Bool {
        return tier.has3D
    }
    
    /// Whether 3D toolpath commands are available.
    public static func canUse3DToolpaths(tier: ProductTier) -> Bool {
        return tier.has3D
    }
    
    /// Whether the Model stage should be hidden entirely.
    /// In Core tier, we keep the stage in the rail (≤12 icons) but show upgrade UI.
    public static func shouldHideModelStage(tier: ProductTier) -> Bool {
        // Never hide — keep rail consistent. Show upgrade prompt instead.
        return false
    }
}

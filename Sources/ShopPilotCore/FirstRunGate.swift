import Foundation

// MARK: - FirstRunGate (UI-polish cluster: onboarding / Kickstarter)

/// Launch-gate state for the welcome sample gallery. SPK-2024a: the gallery
/// is the LANDING VIEW and is shown at every launch, so the gate no longer
/// gates the launch presentation — it persists that the user acknowledged
/// the welcome once (`acknowledge`) and powers the status-bar "Start Making"
/// re-show control (`reset` + re-present, SPK-1603). Pure UserDefaults state
/// so a CLT can prove the transitions.
public enum FirstRunGate {
    private static let key = "shop_pilot_first_run_acknowledged"

    /// True until the user has acknowledged the welcome sheet once.
    public static var isFirstRun: Bool {
        !UserDefaults.standard.bool(forKey: key)
    }

    /// Mark the welcome sheet as acknowledged (never show again).
    public static func acknowledge() {
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Reset for testing/demo — next launch shows the welcome sheet again.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

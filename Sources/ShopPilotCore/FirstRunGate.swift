import Foundation

// MARK: - FirstRunGate (UI-polish cluster: onboarding / Kickstarter)

/// First-launch gate for the welcome/onboarding sheet. Pure UserDefaults
/// state so a CLT can prove the transition (first run → acknowledged →
/// subsequent launches skip the sheet). The reference calls this the
/// "Kickstarter / onboarding" surface; this is the minimal honest slice:
/// one welcome sheet with quick-start CTAs, shown once.
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

import Foundation

// MARK: - Machine-Start Preflight (FM-09 → R016, FM-10 → R017)

/// Engine for machine-start preflight rules. R016 (Z0/datum acknowledgment)
/// lives in `PreflightGate.standard()` as a required item; R017 (thickness
/// drift vs a measured value) is checked here.
public enum MachineStartPreflight {

    /// FM-10 tolerance: |measured − job| above 0.25mm (≈0.01″) drifts too far.
    public static let thicknessDriftToleranceMm: Double = 0.25

    /// R017 — thickness drift warning: when the machine profile carries a
    /// measured material thickness and the job's setup differs by more than
    /// the tolerance, the cut depth may not match reality. Warning with a
    /// "Use Measured Value" CTA.
    public static func thicknessDrift(
        jobThicknessMm: Double,
        measuredThicknessMm: Double?,
        nodeID: UUID = UUID()
    ) -> ToolpathPreflightIssue? {
        guard let measured = measuredThicknessMm else { return nil }
        let drift = abs(measured - jobThicknessMm)
        guard drift > thicknessDriftToleranceMm else { return nil }
        return ToolpathPreflightIssue(
            nodeID: nodeID,
            nodeName: "Machine Start",
            ruleID: "R017",
            severity: .warning,
            message: "Measured material thickness "
                + String(format: "%.2f", measured) + "mm differs from the job setup "
                + String(format: "%.2f", jobThicknessMm) + "mm — verify the cut depth before starting. "
                + "Use the measured value to update the job.",
            fix: .useMeasuredValue
        )
    }
}

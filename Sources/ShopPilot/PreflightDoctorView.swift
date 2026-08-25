import SwiftUI
import ShopPilotGeometry
import ShopPilotCore

// MARK: - Preflight Doctor View (SPK-0211 + SPK-0212)

/// Right-panel vector preflight doctor. Shows the last report's issues with
/// plain-English fix actions; clicking an issue selects the affected shapes
/// on the canvas (and shows the suggested fix in the status bar).
struct PreflightDoctorView: View {
    @ObservedObject var session: AppSession
    /// SPK-2020a — result copy of the last one-tap repair ("N repaired, M remain").
    @State private var repairResultText: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PREFLIGHT")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(severityColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            repairRow

            if let report = session.lastPreflightReport, !report.issues.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(VectorPreflight.fixActions(for: report)) { action in
                            Button {
                                // Find the matching issue for its affected indices.
                                if let issue = report.issues.first(where: {
                                    $0.affectedShapeIndices == action.affectedShapeIndices
                                }) {
                                    session.selectPreflightIssue(issue)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: severityIcon(action.severity))
                                        .foregroundStyle(severityColor(action.severity))
                                        .frame(width: 14)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(action.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text(action.body)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                        if let fix = action.suggestedFix {
                                            Text("Fix: \(fix)")
                                                .font(.caption2)
                                                .foregroundStyle(Color.accentColor)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
                Text("Click an issue to select the affected shapes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: session.lastPreflightReport == nil ? "stethoscope" : "checkmark.seal")
                        .font(.system(size: 30))
                        .foregroundStyle(severityColor)
                    Text(session.lastPreflightReport == nil
                         ? "Run Check Vectors to inspect the design before cutting."
                         : "No vector issues found — good to cut.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - SPK-2020a — one-tap repair row

    /// Join All / Close All / Delete Zero-Span — all route through the
    /// session's undoable `repairVectors()` entry (join + close-count +
    /// zero-span delete), then the preflight report revalidates automatically,
    /// so remaining issues keep the list visible. Disabled when zero problems.
    private var repairRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button("Join All") { performRepair() }
                    .buttonStyle(.bordered)
                Button("Close All") { performRepair() }
                    .buttonStyle(.bordered)
                Button("Delete Zero-Span") { performRepair() }
                    .buttonStyle(.bordered)
                Spacer()
                if hasOpenPathIssues {
                    Button {
                        let r = session.fixOpenVectorsAndReVCarve()
                        noteRepairResult(joined: r.joined, closed: r.closed,
                                         removed: r.removed, remaining: r.remaining)
                    } label: {
                        Label("Fix Open Vectors", systemImage: "wrench.and.screwdriver.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.small)
            if let text = repairResultText {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled((session.lastPreflightReport?.issues.isEmpty ?? true))
    }

    private var hasOpenPathIssues: Bool {
        session.lastPreflightReport?.issues.contains { $0.issue == .openPath } ?? false
    }

    private func performRepair() {
        let result = session.repairVectors()
        noteRepairResult(joined: result.joined, closed: result.closed,
                         removed: result.removed, remaining: result.remaining)
    }

    private func noteRepairResult(joined: Int = 0, closed: Int = 0,
                                  removed: Int = 0, remaining: Int = 0) {
        let repaired = joined + closed + removed
        repairResultText = "\(repaired) repaired, \(remaining) remain"
    }

    private var summaryText: String {
        guard let report = session.lastPreflightReport else { return "not run" }
        if report.issues.isEmpty { return "clean" }
        return "\(report.issues.count) issue\(report.issues.count == 1 ? "" : "s")"
    }

    private var severityColor: Color {
        guard let report = session.lastPreflightReport else { return .secondary }
        switch report.worstSeverity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }

    private func severityColor(_ severity: PreflightSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }

    private func severityIcon(_ severity: PreflightSeverity) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

#if canImport(SwiftUI) && DEBUG
struct PreflightDoctorView_Previews: PreviewProvider {
    static var previews: some View {
        let session = AppSession()
        Text("Preflight doctor preview (session-driven)")
    }
}
#endif

// MARK: - Expanded Vector Validation Panel (SPK-0806)

/// Right-panel summary of the expanded batch validator: per-category error
/// and warning counts with the first few critical issues listed plainly.
/// Pure summary — the deep rule set is proven by ShopPilotVerify0806.
struct VectorValidationPanel: View {
    let result: BatchVectorValidationResult

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("VALIDATION")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if result.criticalErrors.isEmpty && result.totalWarnings == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    Text("All \(result.totalShapes) shapes pass the expanded checks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            stat("Shapes", "\(result.totalShapes)", .primary)
                            stat("Errors", "\(result.totalErrors)", .red)
                            stat("Warnings", "\(result.totalWarnings)", .orange)
                        }

                        if !result.criticalErrors.isEmpty {
                            Text("CRITICAL")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                            ForEach(Array(result.criticalErrors.prefix(6).enumerated()), id: \.offset) { _, entry in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "xmark.octagon.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.errors.map(\.rawValue).joined(separator: ", "))
                                            .font(.caption)
                                        Text(String(format: "%.1f mm path", entry.totalLength))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private var summary: String {
        "\(result.validShapes)/\(result.totalShapes) valid"
    }

    private var statusColor: Color {
        result.criticalErrors.isEmpty ? (result.totalWarnings > 0 ? .orange : .green) : .red
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

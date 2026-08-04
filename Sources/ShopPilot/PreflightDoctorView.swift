import SwiftUI
import ShopPilotGeometry

// MARK: - Preflight Doctor View (SPK-0211 + SPK-0212)

/// Right-panel vector preflight doctor. Shows the last report's issues with
/// plain-English fix actions; clicking an issue selects the affected shapes
/// on the canvas (and shows the suggested fix in the status bar).
struct PreflightDoctorView: View {
    @ObservedObject var session: AppSession

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

import SwiftUI
import ShopPilotCore

struct ContentView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("shop_pilot_pro_skip") private var proSkip = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                StageRailView(selectedStage: $session.selectedStage) { _ in }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                HSplitView {
                    LeftPanelView(session: session)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

                    VStack(spacing: 0) {
                        stageBody
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if !proSkip {
                            CoachPanelView(currentStage: session.selectedStage)
                                .padding(8)
                        }

                        statusBar
                    }

                    InspectorShell(session: session, currentStage: $session.selectedStage)
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                }
            }

            if session.showCommandPalette {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { session.showCommandPalette = false }
                CommandPaletteView(
                    isOpen: $session.showCommandPalette,
                    onCommandSelected: { session.handleCommand($0) }
                )
            }
        }
        .sheet(isPresented: $session.showPreferences) {
            PreferencesView()
                .frame(width: 440, height: 320)
        }
        .sheet(isPresented: $session.showSafetyDisclaimer) {
            SafetyDisclaimerView {
                session.acceptSafety()
            }
        }
    }

    @ViewBuilder
    private var stageBody: some View {
        switch session.selectedStage {
        case .setup:
            SetupStageView(session: session)
        case .design:
            DesignStageView(session: session)
        case .model:
            ModelStageLockedView()
        case .cut:
            CutStageView(session: session)
        case .preview:
            ToolpathPreviewView(session: session)
        case .machine:
            MachineConnectionView(pendingGCode: session.gcodeLines)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(session.statusMessage)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text(session.lastToolpathSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Stage panels

private struct SetupStageView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NewJobView(docVars: session.docVars) { job in
                    session.replaceJob(job)
                }
                DocumentVariablesPanelView(model: session.docVars)
                    .frame(minHeight: 240)
            }
            .padding()
        }
    }
}

private struct DesignStageView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        HSplitView {
            DesignCanvasView(session: session)
            ImportHubView { shapes in
                session.addShapes(shapes)
            }
            .frame(minWidth: 280, idealWidth: 320)
        }
    }
}

private struct ModelStageLockedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Model (3D relief)")
                .font(.title2.bold())
            Text("Requires Studio3D. Use Design + Cut for the v0 demo path.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CutStageView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cut")
                .font(.title2.bold())
            Text("Vectors: \(session.vectors.count) · G-code lines: \(session.gcodeLines.count)")
                .foregroundStyle(.secondary)

            HStack {
                Button("Generate Profile Toolpath") {
                    session.generateProfileToolpath()
                }
                .buttonStyle(.borderedProminent)

                Button("Load Fixture / Built-in G-code") {
                    session.loadFixtureGCodeIfNeeded()
                }

                Button("Send to Machine Stage") {
                    session.loadFixtureGCodeIfNeeded()
                    session.selectedStage = .machine
                }
            }

            if session.gcodeLines.isEmpty {
                Text("No toolpath yet. Add shapes in Design, then generate Profile.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(session.gcodeLines.prefix(80).joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            }
            Spacer()
        }
        .padding()
    }
}


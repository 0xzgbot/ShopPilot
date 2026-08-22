import SwiftUI
import ShopPilotCore

// MARK: - Welcome Sheet (SPK-1400a: "Start Making")

/// First-run welcome sheet: a "Start Making" sheet — headline, then a sample
/// gallery of the four bundled projects from `SampleProjectsStore` (name +
/// tagline, one click loads the sample into the session and dismisses the
/// sheet), then New Job / Open / Import as secondary rows, plus the safety
/// primer. Shown once per machine (FirstRunGate).
///
/// SPK-1400a: the sample list is read straight from `SampleProjectsStore` —
/// never a second hardcoded catalog. "Open…" routes through the real package
/// open path (`session.handleCommand(.openJob)`, the same session routing the
/// File menu uses), and "Import…" presents the same `ImportHubView` flow the
/// Design stage uses — neither is a bare stage switch.
struct WelcomeSheetView: View {
    @ObservedObject var session: AppSession
    var onDone: () -> Void

    /// SPK-1400a — the Import hub (same flow as the Design stage) presented
    /// from this sheet instead of a stage switch.
    @State private var showImportHub = false

    /// The four bundled samples, in display order. The gallery renders this
    /// list directly, so the sheet can never drift from the store.
    private static let samples = SampleProjectsStore.samples

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("Start Making")
                .font(.title2.bold())
            Text("Pick a sample to open it ready to design, or start your own job.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            // Sample gallery — from SampleProjectsStore, never a second list.
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(Self.samples) { sample in
                    Button {
                        if session.loadSampleProject(id: sample.id) {
                            onDone()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Image(systemName: Self.icon(for: sample.category))
                                .font(.system(size: 18))
                                .foregroundStyle(Color.accentColor)
                            Text(sample.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            Text(sample.tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.secondary.opacity(0.25))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Open the \(sample.name) sample")
                }
            }
            .frame(maxWidth: 420)

            VStack(spacing: 8) {
                Button {
                    // SPK-1900c — Photo starter: straight into the photo
                    // import (lithophane mapping), landing in the Model stage.
                    session.generateLithophaneFromPanel()
                    onDone()
                } label: {
                    Label("Start from a Photo…", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    session.selectedStage = .setup
                    onDone()
                } label: {
                    Label("Start a New Job", systemImage: "plus.rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    // Real package open path — the same session routing the
                    // File menu (⌘O) uses (openPackage → FileOperations
                    // loader → applyPackagePayload). Not a stage switch.
                    session.handleCommand(.openJob)
                    onDone()
                } label: {
                    Label("Open a Job…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showImportHub = true
                } label: {
                    Label("Import SVG / DXF / STL…", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 360)

            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Simulate before you cut — software is a complement to a hardware e-stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            Button("Get Started", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 500)
        .sheet(isPresented: $showImportHub) {
            // SPK-1400a — same import flow the Design stage presents.
            ImportHubView(
                onShapesImported: { shapes in
                    session.addShapes(shapes)
                    showImportHub = false
                    onDone()
                },
                onRecordRecent: { url in
                    session.recentFilesStore.record(url)
                },
                recentFiles: session.recentFilesStore.recent,
                clearRecent: {
                    session.recentFilesStore.clear()
                }
            )
            .frame(width: 420, height: 520)
        }
        // Esc dismisses the welcome sheet like any other dialog.
        .onExitCommand { onDone() }
    }

    /// SF Symbol per sample category; falls back to a generic grid icon so a
    /// future category never renders a blank card.
    private static func icon(for category: String) -> String {
        switch category {
        case "Sign": return "sign.postcard.fill"
        case "Box": return "shippingbox.fill"
        case "Keychain": return "key.fill"
        case "Plaque": return "textformat"
        default: return "square.grid.2x2"
        }
    }
}

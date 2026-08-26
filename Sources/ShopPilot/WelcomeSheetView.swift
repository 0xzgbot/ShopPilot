import SwiftUI
import ShopPilotCore

// MARK: - Welcome Sheet (SPK-1400a: "Start Making")

/// Landing view (SPK-2024a): shown at EVERY launch — not a FirstRunGate-only
/// one-shot sheet — and re-presentable from the status-bar "Start Making"
/// control (SPK-1603). Headline, then a sample gallery of the four bundled
/// projects from `SampleProjectsStore` — one click loads the sample through
/// the SPK-1403 loader hooks and lands in the Design stage — then exactly ONE
/// primary forward CTA ("Plan the cuts", into Setup) with "Import Artwork…"
/// as the single secondary, plus the safety primer.
///
/// The sample list is read straight from `SampleProjectsStore` — never a
/// second hardcoded catalog. "Import Artwork…" presents the same
/// `ImportHubView` flow the Design stage uses — not a bare stage switch.
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
                        // SPK-2024a — one click lands IN the Design stage with
                        // the sample loaded. The load itself still goes through
                        // the single SPK-1403 entry point (loadSampleProject →
                        // SampleProjectLoader) — hooks unchanged.
                        if session.loadSampleProject(id: sample.id) {
                            session.selectedStage = .design
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

            // SPK-2024a — exactly ONE primary forward CTA ("Plan the cuts",
            // into the Setup stage) with "Import Artwork…" as the single
            // secondary. New Job / Open / Photo live in the normal chrome
            // (File menu, ⌘O, Model stage), not on the landing view.
            VStack(spacing: 8) {
                Button {
                    session.selectedStage = .setup
                    onDone()
                } label: {
                    Label("Plan the cuts", systemImage: "hammer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button {
                    showImportHub = true
                } label: {
                    Label("Import Artwork…", systemImage: "square.and.arrow.down")
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

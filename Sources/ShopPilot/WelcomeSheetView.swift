import SwiftUI

// MARK: - Welcome Sheet (UI-polish cluster: onboarding / Kickstarter)

/// First-run welcome sheet: three quick-start CTAs (New Job / Open / Import)
/// plus the safety primer, shown once per machine (FirstRunGate). Kept small
/// and dismissible — it routes to existing stages rather than locking the UI.
struct WelcomeSheetView: View {
    @ObservedObject var session: AppSession
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to ShopPilot")
                .font(.title2.bold())
            Text("Design vectors, generate toolpaths, and run your CNC router — all on the Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            VStack(spacing: 8) {
                Button {
                    session.selectedStage = .setup
                    onDone()
                } label: {
                    Label("Start a New Job", systemImage: "plus.rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    session.selectedStage = .design
                    onDone()
                } label: {
                    Label("Open a Job…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    session.selectedStage = .design
                    onDone()
                } label: {
                    Label("Import SVG / DXF / STL", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 340)

            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Simulate before you cut — software is not a substitute for a hardware e-stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            Button("Get Started", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 460)
    }
}

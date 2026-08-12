import SwiftUI

// MARK: - Recovery Offer (SPK-1402d)

/// Launch-time "Recover unsaved work?" sheet: an autosave artifact from a
/// previous session exists, and the user can load it (Recover) or clear it
/// (Discard). Presented from ContentView when `session.pendingRecovery` is
/// non-nil on launch. Keep it a quiet, single-decision dialog — no chrome,
/// no nested options.
public struct RecoveryOfferView: View {
    let snapshotName: String
    let modifiedAt: Date
    let onRecover: () -> Void
    let onDiscard: () -> Void

    public init(snapshotName: String,
                modifiedAt: Date,
                onRecover: @escaping () -> Void,
                onDiscard: @escaping () -> Void) {
        self.snapshotName = snapshotName
        self.modifiedAt = modifiedAt
        self.onRecover = onRecover
        self.onDiscard = onDiscard
    }

    private var modifiedText: String {
        modifiedAt.formatted(date: .abbreviated, time: .shortened)
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.accentColor)

            Text("Recover unsaved work?")
                .font(.title3.bold())

            Text("“\(snapshotName)” was being edited when it last closed "
                 + "(\(modifiedText)). Load the autosave and keep going?")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 10) {
                Button("Discard", role: .destructive, action: onDiscard)
                    .buttonStyle(.bordered)
                Button("Recover", action: onRecover)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 420)
        // Esc dismisses like any other dialog — same as Discard.
        .onExitCommand { onDiscard() }
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
struct RecoveryOfferView_Previews: PreviewProvider {
    static var previews: some View {
        RecoveryOfferView(snapshotName: "Plaque Project",
                          modifiedAt: .now.addingTimeInterval(-3600),
                          onRecover: {}, onDiscard: {})
    }
}
#endif

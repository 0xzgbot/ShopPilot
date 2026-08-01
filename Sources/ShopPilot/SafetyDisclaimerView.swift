import SwiftUI

/// In-app safety disclaimer required before machine use.
struct SafetyDisclaimerView: View {
    var onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Safety Notice")
                .font(.title2.bold())

            Text(
                """
                ShopPilot software controls are not a substitute for a hardware emergency stop.

                Always:
                • Keep a hardware e-stop within reach
                • Air-cut (simulate) before cutting material
                • Confirm work zero, tool, and clamps before Start
                • Never leave a running machine unattended

                By continuing you acknowledge you are responsible for safe machine operation.
                """
            )
            .font(.body)

            HStack {
                Spacer()
                Button("I Understand") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .interactiveDismissDisabled(true)
    }
}

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("ShopPilot")
                .font(.title)
                .fontWeight(.bold)

            Text("CNC Suite — Ready for development")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.title2)
                    Text("Machine Control")
                        .font(.caption)
                    Text("Track A — GRBL/FluidNC serial")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    Image(systemName: "pen.toolpath")
                        .font(.title2)
                    Text("Studio / CAM")
                        .font(.caption)
                    Text("Track B — Aspire-class design")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            Spacer()
        }
        .padding()
    }
}

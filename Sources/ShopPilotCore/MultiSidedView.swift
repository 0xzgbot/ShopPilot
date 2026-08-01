#if canImport(SwiftUI)

import SwiftUI

// MARK: - MultiSidedView

/// A SwiftUI view that displays front/back side tabs for a double-sided job.
public struct MultiSidedView: View {
    @Binding var config: DoubleSidedJobConfig
    @State private var flipAnimating: Bool = false
    
    public init(config: Binding<DoubleSidedJobConfig>) {
        self._config = config
        self._activeSide = State(initialValue: config.wrappedValue.frontSheetID != UUID() ? .front : .back)
    }
    
    @State private var activeSide: JobSide
    
    public var body: some View {
        VStack(spacing: 0) {
            sideToggleBar
            
            if !config.registrationMarks.isEmpty {
                registrationMarksOverlay
            }
            
            if flipAnimating {
                flipIndicator
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: flipAnimating)
    }
    
    // MARK: - Side Toggle Bar
    
    private var sideToggleBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                if activeSide != .front {
                    activeSide = .front
                    flipAnimating = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation {
                            flipAnimating = false
                        }
                    }
                }
            }) {
                sideButtonLabel(side: .front, isActive: activeSide == .front)
            }
            .buttonStyle(SideToggleStyle())
            
            Button(action: {
                if activeSide != .back {
                    activeSide = .back
                    flipAnimating = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation {
                            flipAnimating = false
                        }
                    }
                }
            }) {
                sideButtonLabel(side: .back, isActive: activeSide == .back)
            }
            .buttonStyle(SideToggleStyle())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func sideButtonLabel(side: JobSide, isActive: Bool) -> some View {
        VStack(spacing: 2) {
            Text(side.rawValue.capitalized)
                .font(.headline)
            Text(side == .front ? "Front" : "Back")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isActive ? .white : .primary)
    }
    
    // MARK: - Registration Marks Overlay
    
    private var registrationMarksOverlay: some View {
        ZStack {
            ForEach(config.registrationMarks) { mark in
                if mark.detected {
                    Circle()
                        .stroke(Color.orange, lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                        .position(x: mark.x, y: mark.y)
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Flip Animation Indicator
    
    private var flipIndicator: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .rotationEffect(.degrees(flipAnimating ? 360 : 0))
                .animation(.linear(duration: 0.5).repeatCount(3, autoreverses: false), value: flipAnimating)
            Text("Flipping to \(activeSide.rawValue.capitalized) side...")
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.95))
        .cornerRadius(8)
    }
}

// MARK: - Side Toggle Style

private struct SideToggleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .background(configuration.isPressed ? Color.blue.opacity(0.8) : Color.blue)
            .cornerRadius(6)
    }
}

// MARK: - Preview (Xcode only)

#if DEBUG
struct MultiSidedView_Previews: PreviewProvider {
    static var previews: some View {
        Text("MultiSidedView preview requires Xcode Previews")
    }
}
#endif

#endif // canImport(SwiftUI)

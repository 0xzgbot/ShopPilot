import SwiftUI

// MARK: - Design tool palette

/// Image-editor-style vertical tool rail for the Design
/// stage. Each canvas create tool is an icon button; the active tool gets the
/// brand capsule. Option-key shortcuts (⌥V / ⌥R / ⌥O / ⌥L / ⌥P) match
/// Photoshop muscle memory without colliding with typing in text fields.
struct DesignToolPaletteView: View {
    @Binding var tool: CanvasCreateTool

    var body: some View {
        VStack(spacing: 6) {
            ForEach(CanvasCreateTool.allCases) { t in
                toolButton(t)
            }
            Spacer(minLength: 6)
        }
        .padding(.vertical, 8)
        .frame(width: 46)
        .background(.thinMaterial)
        .overlay(alignment: .trailing) { Divider() }
    }

    private func toolButton(_ t: CanvasCreateTool) -> some View {
        Button {
            tool = t
        } label: {
            Image(systemName: t.symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 30, height: 30)
                .background {
                    if tool == t {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.22))
                    }
                }
                .overlay {
                    if tool == t {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                    }
                }
                .foregroundStyle(tool == t ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .help(t.hint)
        .accessibilityLabel(t.label)
        .accessibilityAddTraits(.isButton)
        .keyboardShortcut(shortcutKey(t), modifiers: .option)
    }

    private func shortcutKey(_ t: CanvasCreateTool) -> KeyEquivalent {
        switch t {
        case .select: return "v"
        case .rect: return "r"
        case .circle: return "o"
        case .line: return "l"
        case .polyline: return "p"
        }
    }
}

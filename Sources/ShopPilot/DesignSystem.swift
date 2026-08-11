import SwiftUI

// MARK: - Design tokens

/// ShopPilot's shared chrome vocabulary. Every surface in the global shell —
/// top chrome, stage rail, browser, inspector, status bar, machine safety
/// chrome — draws its spacing, radii, type and semantic tint from here so the
/// window reads as one Mac app rather than several bolted-together panels.
enum SP {

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 7
        static let panel: CGFloat = 10
        static let overlay: CGFloat = 14
    }

    enum Motion {
        /// Stage rail selection travel.
        static let stage = Animation.spring(response: 0.34, dampingFraction: 0.86)
        /// Connection / stream state changes.
        static let state = Animation.spring(response: 0.26, dampingFraction: 0.90)
        /// Alarm banner arrival — fast enough to read as urgent, damped enough
        /// not to bounce like a toy.
        static let alarm = Animation.spring(response: 0.22, dampingFraction: 0.72)
    }

    enum Typography {
        static let sectionLabel = Font.caption2.weight(.semibold)
        static let stageTitle = Font.title3.weight(.semibold)
        static let rowTitle = Font.system(size: 13)
        /// Digital read-out numbers (positions, line counts, feeds).
        static let dro = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
    }

    /// Semantic tint. Red is reserved for machine safety — Reset and alarms —
    /// per AGENTS.md §2 and the UX density budget.
    enum Tint {
        /// Brand accent — warm wood-shop amber (matches the app icon + the
        /// material palettes). Applied as the app-wide accent so buttons,
        /// selection and focus read as one brand, not default system blue.
        static let brand = Color(red: 0.93, green: 0.60, blue: 0.18)
        static let safety = Color.red
        static let hold = Color.orange
        /// Spindle is moving.
        static let running = Color.green
        /// Connected and standing still. Deliberately not `running`: "the
        /// machine is powered and waiting" and "the machine is cutting" must be
        /// distinguishable at a glance across a shop.
        static let ready = Color.blue
        /// Nothing connected.
        static let idle = Color.secondary
    }
}

// MARK: - Section label

/// Uppercase group label used by the browser, inspector and machine panels.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(SP.Typography.sectionLabel)
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Sidebar chrome

/// Header strip shared by the left browser and right inspector so both
/// sidebars share the same 28pt rhythm as the top chrome's inner rows.
struct SidebarHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: SP.Space.xs) {
            SectionLabel(title)
            Spacer(minLength: SP.Space.xs)
            trailing
        }
        .frame(height: 28)
        .padding(.horizontal, SP.Space.m)
    }
}

extension SidebarHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

extension View {
    /// Sidebar surface: vibrant material, hairline edge toward the canvas.
    func spSidebar(edge: Edge) -> some View {
        self
            .background(.thinMaterial)
            .overlay(alignment: edge == .leading ? .leading : .trailing) {
                Divider()
            }
    }
}

// MARK: - Empty state

/// Quiet first-run surface: one symbol, one sentence, one action. Deliberately
/// not a dashboard — the UX plan calls for confidence, not statistics.
struct EmptyStage: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: SP.Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: SP.Space.xs) {
                Text(title)
                    .font(SP.Typography.stageTitle)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SP.Space.xl)
    }
}

// MARK: - Machine chrome state

/// Glanceable machine state for the global chrome. Mirrors the connection and
/// streamer state owned by the Machine stage — it never commands the machine
/// on its own.
public enum MachineChromeState: Equatable {
    case offline
    case connecting
    case idle
    case running(progress: Double)
    case hold
    case alarm(String)

    var label: String {
        switch self {
        case .offline: return "Not connected"
        case .connecting: return "Connecting"
        case .idle: return "Idle"
        case .running: return "Running"
        case .hold: return "Hold"
        case .alarm: return "Alarm"
        }
    }

    var symbol: String {
        switch self {
        case .offline: return "cable.connector.slash"
        case .connecting: return "cable.connector"
        case .idle: return "checkmark.circle.fill"
        case .running: return "play.fill"
        case .hold: return "pause.fill"
        case .alarm: return "exclamationmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .offline: return SP.Tint.idle
        case .connecting: return SP.Tint.hold
        case .idle: return SP.Tint.ready
        case .running: return SP.Tint.running
        case .hold: return SP.Tint.hold
        case .alarm: return SP.Tint.safety
        }
    }

    /// True while the transport is open — safety controls must be reachable.
    var isLive: Bool {
        switch self {
        case .offline: return false
        default: return true
        }
    }

    /// Motion is paused, so the operator's next safety action is Resume rather
    /// than Hold.
    var isHeld: Bool {
        if case .hold = self { return true }
        return false
    }

    var detail: String? {
        if case .alarm(let message) = self { return message }
        return nil
    }
}

// MARK: - Machine state pill

/// Glanceable connection state for the top chrome. Tapping it jumps to the
/// Machine stage; it never sends a command.
struct MachineStatePill: View {
    let state: MachineChromeState
    /// Drop the word and keep the glyph when the safety controls need the room.
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: state.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(state.tint)

                if !compact {
                    Text(state.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(state.isLive ? .primary : .secondary)
                }

                if case .running(let progress) = state {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, SP.Space.s)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(state.tint.opacity(state.isLive ? 0.14 : 0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(state.tint.opacity(state.isLive ? 0.35 : 0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("Machine state — \(state.detail ?? state.label). Click to open the Machine stage.")
        .accessibilityLabel("Machine state: \(state.detail ?? state.label)")
    }
}

// MARK: - Compact safety controls

/// Hold (or Resume) and Reset in the window chrome, shown whenever the machine
/// is live but the Machine stage is not on screen. Safety Req #1: these must
/// never be buried behind navigation. They call straight into the app-lifetime
/// `MachineController`, so they keep working on every stage.
struct CompactSafetyControls: View {
    @ObservedObject var controller: MachineController

    var body: some View {
        HStack(spacing: SP.Space.xs) {
            if controller.chromeState.isHeld {
                Button(action: controller.resume) {
                    Label("Resume", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                }
                .tint(SP.Tint.running)
                .help("Resume — continue the cut")
                .accessibilityLabel("Resume. Continue machine motion")
            } else {
                Button(action: controller.hold) {
                    Label("Hold", systemImage: "pause.fill")
                        .font(.caption.weight(.semibold))
                }
                .tint(SP.Tint.hold)
                .help("Hold — pause motion now")
                .accessibilityLabel("Hold. Pause machine motion")
            }

            Button(action: controller.reset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.semibold))
            }
            .tint(SP.Tint.safety)
            .help("Reset — stop and clear the controller")
            .accessibilityLabel("Reset. Stop and clear the machine")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .fixedSize()
    }
}

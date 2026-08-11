import SwiftUI
import ShopPilotCore

// MARK: - Coach Panel View

/// A contextual coaching strip under the canvas. SPK-1205: the message comes
/// from the rule engine (`CoachRuleEngine`) — blocking issues > empty states
/// > suggestions — with the static per-stage fallback when no rule matches
/// (no dead air). The app builds a `CoachContext` from the live session and
/// passes it in, so the strip reacts to what's actually on screen.
public struct CoachPanelView: View {
    @State private var dismissed = false
    @State private var lastActivityTime = Date.now

    let currentStage: Stage

    /// SPK-0318 — follow-source state driving the Cut coach copy.
    let followSourceMode: FollowSourceMode?
    let activeFollowLinkCount: Int

    /// SPK-1205 — the live session snapshot the rules evaluate against.
    let context: CoachContext

    init(currentStage: Stage,
         followSourceMode: FollowSourceMode? = nil,
         activeFollowLinkCount: Int = 0,
         context: CoachContext? = nil) {
        self.currentStage = currentStage
        self.followSourceMode = followSourceMode
        self.activeFollowLinkCount = activeFollowLinkCount
        self.context = context ?? CoachContext(stage: currentStage.rawValue)
    }

    private var coachMessage: String {
        // SPK-1205 — rule engine first: blocking > empty > suggestion.
        if let rule = CoachRuleEngine.resolve(rules: CoachRuleEngine.standardRules, context: context) {
            return rule.message
        }
        // Fallback: the static per-stage copy (existing behavior).
        return staticMessage
    }

    private var staticMessage: String {
        switch currentStage {
        case .setup:
            return "Start by selecting your material and setting up the sheet dimensions. Accurate setup ensures correct toolpaths."
        case .design:
            return "Import or draw vector shapes on layers. Each layer can have its own visibility and lock state for organized design work."
        case .model:
            if !FeatureFlag.isAvailable(.modelStage3D, tier: ProductTier.core) {
                return "3D relief features require Studio3D upgrade. Create your 2D design in the Design stage first, then add toolpaths in the Cut stage."
            }
            return "Create 3D reliefs, combine components, or sculpt surfaces. Use the shape tools to add depth and detail to your design."
        case .cut:
            if let mode = followSourceMode {
                return CoachCopy.followSourceCutMessage(mode: mode, activeLinkCount: activeFollowLinkCount)
            }
            if !FeatureFlag.isAvailable(.quickEngrave, tier: ProductTier.studio) {
                return "Choose a toolpath strategy (Profile, Pocket, Drill) and link it to vectors on your layers. Toolpaths don't follow art unless linked — select your vectors first, then apply the strategy."
            }
            return "Choose a toolpath strategy (Profile, Pocket, Drill, V-Carve) and link it to vectors on your layers. For signs: use V-Carve with a V-bit for lettering (deeper cuts = wider grooves). Select your vectors first, then apply the strategy. V-Carve shading creates engraved lettering effects."
        case .preview:
            return "Review the simulated toolpath with heightfield visualization. Check for collisions, verify depths, and confirm feed rates."
        case .machine:
            return "Connect via simulator or serial cable. Run a pre-flight checklist, then air-cut to verify before committing to material."
        }
    }

    /// Coach glyphs follow the stage rail so the same stage never wears two
    /// different symbols (ICON_INVENTORY §1 audit).
    private var coachIcon: String {
        currentStage == .preview ? "eye" : currentStage.icon
    }

    public var body: some View {
        if !dismissed {
            // A quiet strip along the bottom of the canvas, not a floating
            // card — guidance should sit under the work, not on top of it.
            HStack(alignment: .top, spacing: SP.Space.s) {
                Image(systemName: coachIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                    .frame(height: 16)

                Text(coachMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: SP.Space.s)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Hide tips for this session")
                .accessibilityLabel("Hide tip")
            }
            .padding(.horizontal, SP.Space.m)
            .padding(.vertical, SP.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4))
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func dismiss() {
        dismissed = true
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
struct CoachPanelView_Previews: PreviewProvider {
    static var previews: some View {
        CoachPanelView(currentStage: .design)
            .padding()
    }
}
#endif

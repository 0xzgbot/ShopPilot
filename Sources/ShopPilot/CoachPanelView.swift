import SwiftUI
import ShopPilotCore

// MARK: - Coach Panel View

/// A contextual coaching tip card under the canvas. SPK-1205: the message
/// comes from the rule engine (`CoachRuleEngine`) — blocking issues > empty
/// states > suggestions — with the static per-stage fallback when no rule
/// matches (no dead air). The app builds a `CoachContext` from the live
/// session and passes it in, so the card reacts to what's actually on screen.
/// SPK-1400f: the strip became a real tip card — icon badge + message + an
/// optional action `Button` when the resolved rule carries an `actionID`
/// (same `CoachRuleEngine`, no second rule system).
public struct CoachPanelView: View {
    @State private var dismissed = false
    @State private var lastActivityTime = Date.now

    let currentStage: Stage

    /// SPK-0318 — follow-source state driving the Cut coach copy.
    let followSourceMode: FollowSourceMode?
    let activeFollowLinkCount: Int

    /// SPK-1205 — the live session snapshot the rules evaluate against.
    let context: CoachContext

    /// SPK-1400f — invoked when the tip card's action button is pressed;
    /// receives the resolved rule so the caller can route by `actionID`.
    /// Defaults to nil (callers that only show guidance don't need it; the
    /// button is still rendered when a rule carries an action id).
    let onAction: ((CoachRule) -> Void)?

    init(currentStage: Stage,
         followSourceMode: FollowSourceMode? = nil,
         activeFollowLinkCount: Int = 0,
         context: CoachContext? = nil,
         onAction: ((CoachRule) -> Void)? = nil) {
        self.currentStage = currentStage
        self.followSourceMode = followSourceMode
        self.activeFollowLinkCount = activeFollowLinkCount
        self.context = context ?? CoachContext(stage: currentStage.rawValue)
        self.onAction = onAction
    }

    /// The single resolved rule — the card reads both the message and the
    /// optional action from it, so the tip and its button always agree.
    private var resolvedRule: CoachRule? {
        CoachRuleEngine.resolve(rules: CoachRuleEngine.standardRules, context: context)
    }

    private var coachMessage: String {
        // SPK-1205 — rule engine first: blocking > empty > suggestion.
        if let rule = resolvedRule {
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
            // SPK-1400f — a quiet tip card under the canvas, not a floating
            // overlay: icon badge + message + optional action Button when the
            // resolved rule carries an action id. Guidance sits under the
            // work, never on top of it; SF Symbols only, no extra chrome.
            HStack(alignment: .center, spacing: SP.Space.m) {
                Image(systemName: coachIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: SP.Radius.control, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tip")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)

                    Text(coachMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: SP.Space.s)

                if let rule = resolvedRule, rule.actionID != nil {
                    Button {
                        onAction?(rule)
                    } label: {
                        Text(rule.actionTitle ?? "Learn more")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(rule.actionTitle ?? "Learn more")
                }

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
            .background(
                RoundedRectangle(cornerRadius: SP.Radius.panel, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SP.Radius.panel, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
            .padding(.horizontal, SP.Space.m)
            .padding(.vertical, SP.Space.s)
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

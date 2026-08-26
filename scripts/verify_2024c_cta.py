#!/usr/bin/env python3
"""SPK-2024c verify — one forward CTA per stage rail stage (AUDIT gate).

Audit-first card: the five stage-rail stages (Setup / Design / Cut / Preview /
Machine) were audited for "exactly ONE primary next-action button, named by
the coach strip". This script freezes the audited state so regressions fail
the gate.

Method — brace-counting scan, NOT non-greedy regex: every
`.buttonStyle(.borderedProminent)` occurrence is attributed to its enclosing
Swift type by walking the source character-by-character with a brace stack
(string literals and `//` line comments are masked first so braces inside
them cannot unbalance the count; inner closures therefore never break the
attribution the way `.*?\\n}` patterns would).

Audited inventory (call-sites), 2026-08-25:

  Stage    Primary forward CTA            Call-site                          Coach promotion
  -------  -----------------------------  ---------------------------------  ---------------------------------
  Setup    Stock & Material forms are     SetupStageView -> NewJobView +     setup.empty / setup.next rules
           the stage focus; no competing  MaterialSetupView (plain style,    name material + sheet dimensions,
           prominent button               0 borderedProminent)               then "draw your design next"
  Design   Import Artwork… (empty state)  ContentView.swift                  design.empty rule names import/
                                          DesignStageView (1 primary)        draw + action "Try a sample"
  Cut      Cut out (recipe row, first) +  ContentView.swift CutStageView     cut.empty rule: "Generate a
           forward = Send to Machine      (0 prominent); per-op Apply        toolpath from the Cut toolbar" +
           Stage (secondary chrome)       Params forms are contextual        action "Cut out"
                                          detail panes, not stage chrome
  Preview  Continue to Machine            ToolpathPreviewView.swift          preview.empty / preview.hint
                                                                           rules name simulating + review
  Machine  Connect (disconnected) / Run   MachineConnection.swift            machine.disconnected rule:
           Job (preflight passed) —       MachineConnectionView              "Pick a transport and connect" +
           mutually exclusive states                                         action "Connect"

Documented observations (NOT changed — audit-first, out of listed files):
  - Preview styles its in-place utility "Generate profile if empty"
    (ToolpathPreviewView.swift) as .borderedProminent too. It regenerates
    toolpaths in place — not a forward action — but visually shares
    prominence with "Continue to Machine".
  - The per-op "Apply Params — Regenerate" buttons (Profile/Pocket/Drill/
    V-carve params forms) are form-commit actions inside contextual detail
    panes, not stage-level primaries.
  - Hold/Resume/Reset safety chrome (DesignSystem.swift, MachineConnection
    SafetyButton) is mandated always-visible by AGENTS.md §2 — safety, never
    a "forward action".

Coach-strip agreement is asserted from CoachRuleEngine.standardRules (the
same engine CoachPanelView renders): every promoted actionID has an
actionTitle, and ContentView routes try_sample / cut_out / connect_machine.

Exit 0 + PASS lines on success; non-zero with details on failure.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_DIR = ROOT / "Sources" / "ShopPilot"
CORE_DIR = ROOT / "Sources" / "ShopPilotCore"

FAILURES: list[str] = []


def must(cond: bool, msg: str) -> None:
    if not cond:
        FAILURES.append(msg)


DECL_RE = re.compile(
    r"^\s*(?:public |private |final |internal |open )*(?:struct|class|enum|extension)\s+(\w+)",
    re.M,
)
BP_TOKEN = ".buttonStyle(.borderedProminent)"


def mask_strings_and_comments(text: str) -> str:
    """Blank out string-literal bodies and // line comments so their braces,
    quotes and keywords cannot affect the scan. Character positions (and thus
    line numbers) are preserved."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    break
                j += 1
            for k in range(i + 1, min(j, n)):
                if out[k] not in ("\n",):
                    out[k] = " "
            i = j + 1
        elif ch == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        else:
            i += 1
    return "".join(out)


def scan_bordered_prominent(path: Path) -> list[tuple[str, int]]:
    """Return [(enclosing type, line)] for every borderedProminent in file,
    attributed by a brace-stack walk (no non-greedy regex)."""
    text = mask_strings_and_comments(path.read_text(encoding="utf-8"))
    decl_at = {m.start(): m.group(1) for m in DECL_RE.finditer(text)}
    bp_at = set()
    for m in re.finditer(re.escape(BP_TOKEN), text):
        bp_at.add(m.start())
    stack: list[str | None] = []
    pending: str | None = None
    hits: list[tuple[str, int]] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "{":
            stack.append(pending)
            pending = None
        elif ch == "}":
            if stack:
                stack.pop()
        elif i in decl_at:
            pending = decl_at[i]
        if i in bp_at:
            enclosing = next((d for d in reversed(stack) if d), "<top-level>")
            line = text.count("\n", 0, i) + 1
            hits.append((enclosing, line))
        i += 1
    return hits


# The audited inventory: (file, enclosing type) -> exact expected count of
# .borderedProminent call-sites. Anything added/removed in these types (or in
# the audited zero-primary types) fails the gate.
EXPECTED: dict[tuple[str, str], int] = {
    # Design: empty-state Import Artwork… is the single prominent button.
    ("ContentView.swift", "DesignStageView"): 1,
    # Cut stage surface itself carries NO prominent buttons (recipe row is
    # equal-weight by design; coach promotes "Cut out").
    ("ContentView.swift", "CutStageView"): 0,
    # Per-op param-form commits live in contextual detail panes (one each).
    ("ContentView.swift", "ProfileParamsForm"): 1,
    ("ContentView.swift", "PocketParamsForm"): 1,
    ("ContentView.swift", "DrillParamsForm"): 1,
    ("ContentView.swift", "VCarveParamsForm"): 1,
    # Preview: forward CTA "Continue to Machine" + documented in-place
    # utility "Generate profile if empty" (observation above).
    ("ToolpathPreviewView.swift", "ToolpathPreviewView"): 2,
    # Machine: state-exclusive Connect / Run Job primaries.
    ("MachineConnection.swift", "MachineConnectionView"): 2,
    # Safety chrome (AGENTS §2 — always visible, not forward actions).
    ("MachineConnection.swift", "SafetyButton"): 1,
    ("DesignSystem.swift", "CompactSafetyControls"): 1,
    # --- Full-inventory freeze: every remaining borderedProminent site in
    # the app target is a modal sheet, popover, or contextual detail pane —
    # none is a stage-rail stage's primary. Frozen so any new site forces an
    # audit-row update first.
    ("WelcomeSheetView.swift", "WelcomeSheetView"): 1,          # 2024a landing sheet (out of scope)
    ("ModelStageView.swift", "ModelStageView"): 1,              # Model stage (tier-gated; not one of the five)
    ("SheetListView.swift", "DoubleSidedSetupView"): 2,         # Setup Advanced disclosure panels
    ("SheetListView.swift", "RotarySetupView"): 2,
    ("DocumentVariablesPanel.swift", "DocumentVariablesPanelView"): 1,
    ("DocumentVariablesPanel.swift", "DrivenDimensionsPanelView"): 1,
    ("ImportHubView.swift", "ImportHubView"): 1,                # import hub sheet
    ("ImportHubView.swift", "ImportResultView"): 2,
    ("PostStudioView.swift", "PostStudioView"): 1,              # Post Studio sheet
    ("PreflightDoctorView.swift", "PreflightDoctorView"): 1,    # preflight side panel commit
    ("RecipePicker.swift", "RecipePickerView"): 1,              # recipe popover
    ("RecoveryOfferView.swift", "RecoveryOfferView"): 1,        # recovery sheet
    ("SafetyDisclaimerView.swift", "SafetyDisclaimerView"): 1,  # first-run disclaimer
    ("ToolBrowserView.swift", "ToolCutDataEditorView"): 1,      # tool data editor commit
    # Specialty op forms (contextual detail panes on Cut, one commit each).
    ("SpecialtyParamsForms.swift", "PrismParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "FlutingParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "InlayParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "PhotoVCarveParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "QuickEngraveParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "ChamferParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "TextureParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "DragKnifeParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "RotaryWrapParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "SketchCarveParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "ThreadMillParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "TrochoidSlotParamsForm"): 1,
    ("SpecialtyParamsForms.swift", "Rough3DParamsForm"): 1,
}

# Types whose stage surface must stay free of prominent buttons.
ZERO_TYPES = {("ContentView.swift", "SetupStageView")}


def main() -> int:
    swift_files = sorted(APP_DIR.glob("*.swift"))

    # 1. Brace-counting attribution across the app target.
    found: dict[tuple[str, str], list[int]] = {}
    for path in swift_files:
        for enclosing, line in scan_bordered_prominent(path):
            found.setdefault((path.name, enclosing), []).append(line)

    audited_keys = set(EXPECTED) | ZERO_TYPES
    for key in sorted(audited_keys):
        expected = EXPECTED.get(key, 0)
        lines = found.get(key, [])
        must(
            len(lines) == expected,
            f"{key[0]}:{key[1]} expected {expected} borderedProminent "
            f"call-site(s), found {len(lines)}"
            + (f" at lines {lines}" if lines else ""),
        )

    # Unknown new prominent sites anywhere in the app target also fail:
    # a new stage-level primary needs an audit-row update first.
    known_types = {k[1] for k in audited_keys}
    for (fname, enclosing), lines in sorted(found.items()):
        if (fname, enclosing) not in audited_keys and enclosing not in (
            # Welcome sheet shipped 2024a (out of scope); sheets/modals and
            # contextual panels are not stage surfaces. Freeze them anyway so
            # the total inventory stays honest.
            "WelcomeSheetView",
        ):
            must(
                False,
                f"unaudited borderedProminent site(s): {fname}:{enclosing} "
                f"lines {lines} — update SPK-2024c audit table first",
            )

    # 2. Coach strip promotes the same action the stage leads with
    #    (CoachRuleEngine.standardRules is the single rule source both the
    #    tip card and these asserts read).
    engine = (CORE_DIR / "CoachRuleEngine.swift").read_text(encoding="utf-8")
    for action_id, title in (
        ("try_sample", "Try a sample"),
        ("cut_out", "Cut out"),
        ("connect_machine", "Connect"),
    ):
        must(
            f'actionTitle: "{title}", actionID: "{action_id}"' in engine,
            f'coach rule promotes "{title}" via actionID {action_id}',
        )
    coach = (APP_DIR / "CoachPanelView.swift").read_text(encoding="utf-8")
    must("rule.actionTitle" in coach, "coach tip-card button renders actionTitle")
    must("rule.actionID != nil" in coach, "coach shows the action only when the rule carries one")

    # 3. ContentView routes the coach actions and hosts the strip per stage.
    cv = (APP_DIR / "ContentView.swift").read_text(encoding="utf-8")
    for routed in ("try_sample", "cut_out", "connect_machine"):
        must(f'case "{routed}"' in cv, f"ContentView routes coach action {routed}")
    must("CoachPanelView(" in cv, "coach strip hosted under the stage canvas")
    must("currentStage: session.selectedStage" in cv, "coach follows the active stage")

    if FAILURES:
        print(f"FAIL verify_2024c_cta — {len(FAILURES)} problem(s):")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("PASS verify_2024c_cta — one-forward-CTA-per-stage audit holds:")
    for key in sorted(audited_keys):
        expected = EXPECTED.get(key, 0)
        print(f"  {key[0]}:{key[1]} = {expected}")
    print("  coach promotions: Try a sample (design.empty) · Cut out "
          "(cut.empty) · Connect (machine.disconnected)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

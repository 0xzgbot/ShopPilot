#!/usr/bin/env python3
"""SPK-1603 verify — Welcome can return (+ SPK-2024a landing-view contract).

Asserts, by reading Sources/ShopPilot/ContentView.swift,
Sources/ShopPilot/WelcomeSheetView.swift and Sources/ShopPilot/AppSession.swift:

SPK-2024a (welcome gallery = landing view):
  A1. The launch path shows the welcome landing UNCONDITIONALLY: no
      `FirstRunGate.isFirstRun` gate remains around `showWelcome = true`.
  A2. The gallery renders SampleProjectsStore.samples directly (no second
      catalog): the view's sample list is `SampleProjectsStore.samples` and
      the file constructs no `SampleProject(` literals of its own.
  A3. One click on a sample loads it AND lands in Design: the sample button
      calls `session.loadSampleProject(id:` (the SPK-1403 entry point) and
      then sets `session.selectedStage = .design`.
  A4. The SPK-1403 loader hooks are preserved end-to-end: AppSession still
      delegates to `SampleProjectLoader.load(id:into:)`.
  A5. Exactly ONE primary CTA: exactly one `.borderedProminent`, labeled
      "Plan the cuts", its action switches to `.setup`, and it is the
      default-action keyboard shortcut (exactly one such shortcut).
  A6. "Import Artwork…" is the secondary CTA (bordered).
  A7. The retired welcome CTAs are gone from the landing: Start from a
      Photo / Start a New Job / Open a Job / Get Started appear nowhere in
      the view (their flows live in normal chrome).

SPK-1603 (Welcome can return):
  B1. A visible chrome control re-presents the sheet (`FirstRunGate.reset()`
      + `showWelcome = true` together, after the dismiss acknowledge site).
  B2. Dismiss still acknowledges (`FirstRunGate.acknowledge()`).
  B3. The re-show control is NOT in App.swift (Help menu is 1605's job).
  B4. The re-presented sheet is the same WelcomeSheetView.

Exit 0 + PASS line on success; non-zero with details on failure.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "Sources" / "ShopPilot" / "ContentView.swift"
APP = ROOT / "Sources" / "ShopPilot" / "App.swift"
WELCOME = ROOT / "Sources" / "ShopPilot" / "WelcomeSheetView.swift"
SESSION = ROOT / "Sources" / "ShopPilot" / "AppSession.swift"

FAILURES: list[str] = []


def must(cond: bool, msg: str) -> None:
    if not cond:
        FAILURES.append(msg)


def main() -> int:
    content = CONTENT.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")
    welcome = WELCOME.read_text(encoding="utf-8")
    session = SESSION.read_text(encoding="utf-8")

    # ── SPK-2024a: landing view ─────────────────────────────────────────────
    # A1. Launch shows the landing unconditionally.
    must("isFirstRun" not in content,
         "launch path shows the landing unconditionally (no isFirstRun gate left)")
    must(content.count("showWelcome = true") >= 2,
         "welcome is shown at launch AND re-showable (>=2 show sites)")

    # A2. Single catalog: the gallery reads the store directly.
    must("private static let samples = SampleProjectsStore.samples" in welcome,
         "gallery list is SampleProjectsStore.samples (no second catalog)")
    must(re.search(r"(?<![A-Za-z])SampleProject\(", welcome) is None,
         "welcome view constructs no SampleProject literals of its own")

    # A3. Sample click → load via SPK-1403 entry point, then land in Design.
    load_idx = welcome.find("session.loadSampleProject(id:")
    design_idx = welcome.find("session.selectedStage = .design")
    must(load_idx >= 0 and design_idx > load_idx,
         "sample click loads via loadSampleProject THEN lands in Design stage")

    # A4. Loader hooks preserved end-to-end.
    must("SampleProjectLoader.load(id: id, into: self)" in session,
         "AppSession still delegates to SampleProjectLoader.load (SPK-1403 hooks)")

    # A5. Exactly ONE primary CTA.
    must(welcome.count(".borderedProminent") == 1,
         "exactly one primary (.borderedProminent) CTA")
    must('"Plan the cuts"' in welcome,
         "primary CTA is labeled 'Plan the cuts'")
    setup_idx = welcome.find("session.selectedStage = .setup")
    plan_idx = welcome.find('Label("Plan the cuts"')
    must(0 <= setup_idx < plan_idx,
         "'Plan the cuts' forwards to the Setup stage")
    must(welcome.count(".keyboardShortcut(.defaultAction)") == 1,
         "exactly one default-action keyboard shortcut (the primary CTA)")

    # A6. Import Artwork secondary.
    must('Label("Import Artwork…"' in welcome,
         "'Import Artwork…' is the secondary CTA")

    # A7. Retired welcome CTAs are gone.
    for retired in ("Start from a Photo", "Start a New Job",
                    "Open a Job…", 'Button("Get Started"'):
        must(retired not in welcome,
             f"retired CTA removed from the landing: {retired!r}")

    # ── SPK-1603: Welcome can return ────────────────────────────────────────
    # B1. Re-show path: FirstRunGate.reset() + showWelcome = true together.
    must("FirstRunGate.reset()" in content and "showWelcome = true" in content,
         "ContentView has a re-show path (reset + showWelcome = true)")
    ack_idx = content.find("FirstRunGate.acknowledge()")
    reset_idx = content.find("FirstRunGate.reset()")
    must(reset_idx > ack_idx >= 0,
         "reset() call site is separate from the dismiss acknowledge()")

    # B2. Dismiss still acknowledges.
    must("FirstRunGate.acknowledge()" in content,
         "dismiss still acknowledges (FirstRunGate.acknowledge)")

    # B3. Not in App.swift (Help menu is 1605's job).
    must("showWelcome" not in app and "WelcomeSheetView" not in app,
         "re-show control is NOT in App.swift")

    # B4. The sheet is still the same WelcomeSheetView.
    must("WelcomeSheetView(session: session)" in content,
         "the re-presented sheet is the same WelcomeSheetView")

    if FAILURES:
        print("1603: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1603+2024a: PASS — Welcome is the every-launch sample-gallery landing "
          "(one click → Design; single 'Plan the cuts' primary + Import Artwork "
          "secondary; SPK-1403 loader hooks intact); re-show + gate reset preserved")
    return 0


if __name__ == "__main__":
    sys.exit(main())

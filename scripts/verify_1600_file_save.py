#!/usr/bin/env python3
"""SPK-1600 verify — File Save / Save As.

Asserts, by reading sources:
  1. App.swift File menu has Save (⌘S via registry "file.save") and
     Save As… (⇧⌘S via "file.saveAs").
  2. AppSession.savePackageFromPanel exists: plain Save writes to
     packageURL when set, else presents NSSavePanel; Save As always
     presents the panel; savePackage(to:) sets packageURL (re-save target).
  3. handleCommand(.saveJob) routes to the SAME path (no longer a silent
     Documents default dump as the only Save).
  4. ShortcutRegistry has file.save / file.saveAs entries (remappable).

Exit 0 + PASS line on success; non-zero with details on failure.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

FAILURES: list[str] = []


def must(cond: bool, msg: str) -> None:
    if not cond:
        FAILURES.append(msg)


def main() -> int:
    app = (ROOT / "Sources" / "ShopPilot" / "App.swift").read_text(encoding="utf-8")
    session = (ROOT / "Sources" / "ShopPilot" / "AppSession.swift").read_text(encoding="utf-8")
    registry = (ROOT / "Sources" / "ShopPilotCore" / "ShortcutRegistry.swift").read_text(encoding="utf-8")

    # 1. File menu has Save + Save As.
    must('Button("Save")' in app and 'Button("Save As…")' in app,
         "App.swift File menu has Save and Save As…")
    must('session.savePackageFromPanel()' in app,
         "Save calls savePackageFromPanel() (prompts when no packageURL)")
    must('session.savePackageFromPanel(isSaveAs: true)' in app,
         "Save As… calls savePackageFromPanel(isSaveAs: true)")

    # 2. Panel behavior in AppSession.
    must("func savePackageFromPanel(isSaveAs: Bool = false)" in session,
         "AppSession.savePackageFromPanel exists")
    must("if !isSaveAs, let packageURL" in session,
         "plain Save re-saves to packageURL when known")
    must("NSSavePanel()" in session,
         "first save / Save As presents NSSavePanel")
    must("panel.allowedContentTypes" in session,
         "panel filters to .shoppilot")
    must("try savePackage(to: url)" in session,
         "panel URL goes through savePackage(to:) (sets packageURL)")

    # 3. .saveJob routes to the same path — not the default dump.
    must("case .saveJob:" in session and "savePackageFromPanel()" in session,
         "handleCommand(.saveJob) routes to savePackageFromPanel (same path)")
    must("savePackageToDefaultLocation" not in session,
         "no silent Documents-default dump remains (method removed)")

    # 4. Registry entries.
    must('ShortcutBinding(id: "file.save"' in registry,
         "ShortcutRegistry has file.save (⌘S)")
    must('ShortcutBinding(id: "file.saveAs"' in registry,
         "ShortcutRegistry has file.saveAs (⇧⌘S)")

    if FAILURES:
        print("1600: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1600: PASS — File Save / Save As (first save prompts; re-save to packageURL; Save As updates it)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

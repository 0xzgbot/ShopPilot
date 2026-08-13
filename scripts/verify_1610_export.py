#!/usr/bin/env python3
"""SPK-1610 verify — File Export G-code.

Asserts, by reading sources:
  1. App.swift File menu has "Export G-code…" routing through the palette
     command (.exportGcode) with the file.export shortcut (⇧⌘E registry).
  2. AppSession.exportGcodeFromPanel exists — NSSavePanel + post-template
     picker + CutToMachineBridge.export + unit override (the SAME path the
     Cut toolbar's Save Toolpaths uses).
  3. handleCommand(.exportGcode) routes to exportGcodeFromPanel (not the
     old "load fixture + status" stub).
  4. ContentView's saveToolpaths delegates to the session (one shared path).

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
    content = (ROOT / "Sources" / "ShopPilot" / "ContentView.swift").read_text(encoding="utf-8")
    registry = (ROOT / "Sources" / "ShopPilotCore" / "ShortcutRegistry.swift").read_text(encoding="utf-8")

    # 1. File menu + shortcut.
    must('Button("Export G-code…")' in app
         and "session.handleCommand(.exportGcode)" in app,
         "App.swift File menu has Export G-code… via the palette command")
    must('ShortcutBinding(id: "file.export"' in registry,
         "ShortcutRegistry has file.export (⇧⌘E)")

    # 2. Shared session panel.
    must("func exportGcodeFromPanel()" in session,
         "AppSession.exportGcodeFromPanel exists")
    must("NSSavePanel()" in session and "PostTemplatePickerView" in session,
         "panel + post-template picker in the shared path")
    must("CutToMachineBridge.export(" in session
         and "unitsOverride: AppSettings().isInches ? .inch : .millimeter" in session,
         "bridge export + unit override in the shared path")

    # 3. .exportGcode routes to the panel (not the old stub).
    must("case .exportGcode:" in session and "exportGcodeFromPanel()" in session,
         "handleCommand(.exportGcode) → exportGcodeFromPanel")
    must("G-code ready" not in session,
         "old load-fixture-only export stub is gone")

    # 4. Cut toolbar delegates to the session.
    must("session.exportGcodeFromPanel()" in content,
         "ContentView.saveToolpaths delegates to the shared session panel")

    if FAILURES:
        print("1610: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1610: PASS — File Export G-code shares the Cut Save Toolpaths panel (post picker + unit override)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

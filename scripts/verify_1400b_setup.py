#!/usr/bin/env python3
"""SPK-1400b verify — Setup stage advanced disclosure.

Asserts, by reading Sources/ShopPilot/ContentView.swift:
  1. SetupStageView contains DisclosureGroup("Advanced") (the collapse point).
  2. NewJobView and MaterialSetupView appear BEFORE that disclosure (first-run
     priority: stock & material).
  3. SheetListView, DoubleSidedSetupView, RotarySetupView,
     DocumentVariablesPanelView, DrivenDimensionsPanelView, GoldenJobsPanelView
     all appear AFTER (inside) the disclosure — nothing was deleted, just
     collapsed.
  4. Advanced starts collapsed (advancedExpanded = false default).

Exit 0 + one PASS line on success; non-zero with details on failure.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "ShopPilot" / "ContentView.swift"

FAILURES: list[str] = []


def source() -> str:
    return SRC.read_text(encoding="utf-8")


def setup_stage_body(text: str) -> str:
    """Extract the SetupStageView struct body (brace-balanced)."""
    start = text.index("private struct SetupStageView: View {")
    open_brace = text.index("{", start)
    depth = 0
    i = open_brace
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace + 1:i]
        i += 1
    FAILURES.append("SetupStageView struct not closed")
    return ""


def check(body: str, label: str, needle: str, *, before: str | None = None,
          after: str | None = None) -> None:
    if needle not in body:
        FAILURES.append(f"{label}: '{needle}' not found in SetupStageView")
        return
    if before is not None:
        # needle must appear EARLIER than `before` (i.e. before it).
        if body.index(needle) >= body.index(before):
            FAILURES.append(f"{label}: '{needle}' must come BEFORE '{before}'")
    if after is not None:
        # needle must appear LATER than `after` (i.e. inside/after it).
        if body.index(needle) <= body.index(after):
            FAILURES.append(f"{label}: '{needle}' must come AFTER '{after}'")


def main() -> int:
    if not SRC.exists():
        print(f"FAIL — {SRC} not found")
        return 1

    text = source()
    body = setup_stage_body(text)
    if not body:
        print("FAIL — " + "\n".join(FAILURES))
        return 1

    # 1. The collapse point exists.
    check(body, "1", 'DisclosureGroup("Advanced"')

    # 2. NewJob + Material before the disclosure (first-run priority).
    check(body, "2a", "NewJobView(", before='DisclosureGroup("Advanced"')
    check(body, "2b", "MaterialSetupView(", before='DisclosureGroup("Advanced"')

    # 3. All six pro panels inside/after the disclosure (collapsed, not deleted).
    after = 'DisclosureGroup("Advanced"'
    for panel in ("SheetListView(",
                  "DoubleSidedSetupView(",
                  "RotarySetupView(",
                  "DocumentVariablesPanelView(",
                  "DrivenDimensionsPanelView(",
                  "GoldenJobsPanelView("):
        check(body, "3", panel, after=after)

    # 4. Advanced starts collapsed.
    if "advancedExpanded = false" not in text:
        FAILURES.append("4: 'advancedExpanded = false' default not found")

    if FAILURES:
        print("1400b: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1400b: PASS — setup advanced disclosure")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""SPK-1400h verify — Cut left density.

Asserts, by reading Sources/ShopPilot/ContentView.swift (CutStageView):
  1. A DisclosureGroup("More") exists in the Cut left pane.
  2. KeepOutZonesPanel, JobQueuePanelView, PluginsPanelView appear INSIDE that
     disclosure (not as always-expanded siblings of the tool browser).
  3. The default visible left pane keeps Layers/Tree picker + ToolBrowserView
     BEFORE the disclosure (they are not collapsed).
  4. "More" starts collapsed (cutMorePanelsExpanded = false default).
  5. Nothing was deleted — all three panels still exist in the body.

Exit 0 + PASS line on success; non-zero with details on failure.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "ShopPilot" / "ContentView.swift"

FAILURES: list[str] = []


def must(cond: bool, msg: str) -> None:
    if not cond:
        FAILURES.append(msg)


def cut_stage_body(text: str) -> str:
    start = text.index("private struct CutStageView: View {")
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
    raise ValueError("CutStageView not closed")


def main() -> int:
    body = cut_stage_body(SRC.read_text(encoding="utf-8"))

    # 1. The More disclosure exists.
    must('DisclosureGroup("More"' in body, "Cut left has DisclosureGroup(\"More\")")

    more_pos = body.index('DisclosureGroup("More"')

    # 2. The three pro panels live INSIDE the disclosure (after its open).
    for panel in ("KeepOutZonesPanel(", "JobQueuePanelView(", "PluginsPanelView("):
        must(panel in body, f"{panel} still present (not deleted)")
        must(body.index(panel) > more_pos,
             f"{panel} is inside the More disclosure (not an always-open sibling)")

    # 3. Layers/Tree + tool browser stay visible BEFORE the disclosure.
    for keep in ("Picker(\"View\", selection: $cutLayersViewMode)",
                 "ToolBrowserView("):
        must(keep in body and body.index(keep) < more_pos,
             f"{keep} stays visible before the More disclosure")

    # 4. More starts collapsed.
    must("cutMorePanelsExpanded = false" in body,
         "cutMorePanelsExpanded defaults to false (collapsed)")

    if FAILURES:
        print("1400h: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1400h: PASS — cut left density")
    return 0


if __name__ == "__main__":
    sys.exit(main())

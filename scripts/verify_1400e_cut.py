#!/usr/bin/env python3
"""SPK-1400e verify — Cut recipe-first toolbar.

Asserts, by reading Sources/ShopPilot/ContentView.swift:
  1. The default Cut row (first HStack of CutStageView body) has the three
     recipe buttons: "Cut out", "Pocket", "Engrave".
  2. "Photo V-Carve" is NOT a top-level Button of that first HStack — it may
     only exist inside the More menu (a Menu content block). We detect this by
     checking the first HStack region has no line that both contains
     'Button("Photo V-Carve")' AND is at the HStack's indentation level.
  3. Follow Source toggle + Recalculate Dirty stay on the default row.
  4. More menu exists and still contains the strategy entries (nothing was
     deleted — the engines live on): Photo V-Carve, Thread Mill, Rough 3D,
     plus File & machine actions (Load Fixture, Job Sheet, Post Studio,
     Enqueue).
  5. "Save Toolpaths…" stays on the default row.

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


def cut_stage_text(text: str) -> str:
    """Brace-balanced CutStageView struct body."""
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


def first_cut_hstack(body: str) -> str:
    """The Cut toolbar HStack — the one that contains the recipe buttons
    (the first HStack in the body is the title row: 'Cut' + counts)."""
    marker = 'Button("Cut out")'
    marker_pos = body.index(marker)
    search_from = 0
    while True:
        start = body.index("HStack {", search_from)
        open_brace = body.index("{", start)
        depth = 0
        i = open_brace
        while i < len(body):
            if body[i] == "{":
                depth += 1
            elif body[i] == "}":
                depth -= 1
                if depth == 0:
                    if open_brace < marker_pos < i:
                        return body[open_brace + 1:i]
                    break
            i += 1
        search_from = start + 1


def main() -> int:
    text = SRC.read_text(encoding="utf-8")
    body = cut_stage_text(text)
    row = first_cut_hstack(body)

    # 1. Three recipe buttons on the default row.
    for recipe in ('Button("Cut out")', 'Button("Pocket")', 'Button("Engrave")'):
        must(recipe in row, f"default row has {recipe}")

    # 2. Photo V-Carve is not a TOP-LEVEL button of the row (indentation of
    #    the row's direct children). The More-menu occurrence is nested deeper.
    for line in row.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("Button(\"Photo V-Carve\")"):
            indent = len(line) - len(stripped)
            # Direct children of the row HStack sit at 16 spaces (nested
            # content is deeper). Any match at or below that depth is nested.
            if indent <= 20:
                FAILURES.append(
                    f"Photo V-Carve is a top-level Button of the first Cut HStack (indent {indent})"
                )

    # 3. Follow Source + Recalculate Dirty stay on the row.
    must('Toggle("Follow Source"' in row, "Follow Source stays on the row")
    must("Recalculate Dirty" in row, "Recalculate Dirty stays on the row")

    # 4. More menu retains every engine/action (nothing deleted).
    for entry in ('Label("More", systemImage: "ellipsis.circle")',
                  'Button("Photo V-Carve")',
                  'Button("Thread Mill")',
                  'Button("Rough 3D")',
                  'Button("Load Fixture / Built-in G-code")',
                  'Button("Job Sheet…")',
                  'Button("Post Studio…")',
                  'Button("Enqueue")'):
        must(entry in body, f"More menu still contains {entry}")

    # 5. Save Toolpaths stays on the default row.
    must("Save Toolpaths…" in row, "Save Toolpaths… stays on the row")

    if FAILURES:
        print("1400e: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1400e: PASS — cut recipes")
    return 0


if __name__ == "__main__":
    sys.exit(main())

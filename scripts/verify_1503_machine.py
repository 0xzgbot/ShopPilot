#!/usr/bin/env python3
"""SPK-1503 verify — Machine run-controls density.

Asserts, by reading Sources/ShopPilot/MachineConnection.swift:
  1. runControlsPanel wraps its cluster in DisclosureGroup("More") — the
     feed/spindle/touch-off/offset fine-tune controls are collapsible.
  2. Safety chrome unchanged: Jog controls, Hold/Resume/Reset and the alarm
     banner still exist OUTSIDE the run-controls panel (in the main chrome).
  3. SectionLabel("Run Controls") is gone (the disclosure replaces it).

Exit 0 + PASS line on success; non-zero with details on failure.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "ShopPilot" / "MachineConnection.swift"

FAILURES: list[str] = []


def must(cond: bool, msg: str) -> None:
    if not cond:
        FAILURES.append(msg)


def extract_run_controls(text: str) -> str:
    """Brace-balanced body of runControlsPanel."""
    start = text.index("private var runControlsPanel: some View {")
    open_brace = text.index("{", start)
    depth = 0
    i = open_brace
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    return ""


def main() -> int:
    text = SRC.read_text(encoding="utf-8")
    body = extract_run_controls(text)

    # 1. DisclosureGroup("More") present in run controls.
    must('DisclosureGroup("More")' in body,
         "runControlsPanel contains DisclosureGroup(\"More\")")

    # The fine-tune controls are INSIDE the disclosure (not always-expanded
    # siblings).
    more_open = body.index('DisclosureGroup("More")')
    must(body.index('"Spindle ON"') > more_open
         and body.index("Touch-Off") > more_open
         and body.index('"Offset"') > more_open,
         "feed/spindle/touch-off/offset all sit inside the More disclosure")

    # 2. Safety chrome unchanged — these must exist in the file outside the
    # run-controls body (Jog pad + Hold/Resume/Reset + alarm banner).
    must("Hold" in text and "Reset" in text,
         "Hold/Resume/Reset safety controls still present in chrome")
    must("JogButton" in text or '"Jog"' in text,
         "Jog controls still present in chrome")
    content_view = (ROOT / "Sources" / "ShopPilot" / "ContentView.swift").read_text(encoding="utf-8")
    must("MachineAlarmBanner" in content_view,
         "Alarm banner still present (ContentView MachineAlarmBanner)")

    # 3. Old always-expanded header gone.
    must('SectionLabel("Run Controls")' not in text,
         "SectionLabel(\"Run Controls\") removed (replaced by More disclosure)")

    if FAILURES:
        print("1503: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1503: PASS — machine run controls under More disclosure; safety chrome intact")
    return 0


if __name__ == "__main__":
    sys.exit(main())

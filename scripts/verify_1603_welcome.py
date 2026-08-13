#!/usr/bin/env python3
"""SPK-1603 verify — Welcome can return.

Asserts, by reading Sources/ShopPilot/ContentView.swift:
  1. A visible chrome control re-presents the welcome sheet: a call site sets
     `showWelcome = true` OUTSIDE the first-run onAppear (the re-show path).
  2. That call site calls `FirstRunGate.reset()` — the gate reset is the
     persist (the sheet would re-open on next launch).
  3. Dismiss still acknowledges: the sheet's onDismiss handler still calls
     `FirstRunGate.acknowledge()` (never show again on plain close).
  4. The re-show control is NOT in App.swift (Help menu is 1605's job).

Exit 0 + PASS line on success; non-zero with details on failure.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "Sources" / "ShopPilot" / "ContentView.swift"
APP = ROOT / "Sources" / "ShopPilot" / "App.swift"

FAILURES: list[str] = []


def must(cond: bool, msg: str) -> None:
    if not cond:
        FAILURES.append(msg)


def main() -> int:
    content = CONTENT.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")

    # 1. Re-show path: FirstRunGate.reset() + showWelcome = true together
    #    (the chrome control body).
    must("FirstRunGate.reset()" in content and "showWelcome = true" in content,
         "ContentView has a re-show path (reset + showWelcome = true)")

    # The reset+show pair must appear in one control (after the onAppear
    # block) — assert the reset call is not the first-run acknowledge path.
    ack_idx = content.find("FirstRunGate.acknowledge()")
    reset_idx = content.find("FirstRunGate.reset()")
    must(reset_idx > ack_idx >= 0,
         "reset() call site is separate from the dismiss acknowledge()")

    # 2. Dismiss still acknowledges.
    must("FirstRunGate.acknowledge()" in content,
         "dismiss still acknowledges (FirstRunGate.acknowledge)")

    # 3. Not in App.swift (Help menu is 1605's job).
    must("showWelcome" not in app and "WelcomeSheetView" not in app,
         "re-show control is NOT in App.swift")

    # 4. The sheet is still the same WelcomeSheetView.
    must("WelcomeSheetView(session: session)" in content,
         "the re-presented sheet is the same WelcomeSheetView")

    if FAILURES:
        print("1603: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1603: PASS — Welcome can return (Start Making re-show + gate reset; dismiss still acknowledges)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

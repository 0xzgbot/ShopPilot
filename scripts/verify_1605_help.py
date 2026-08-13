#!/usr/bin/env python3
"""SPK-1605 verify — Help menu.

Asserts, by reading Sources/ShopPilot/App.swift:
  1. A Help CommandGroup (replacing .help) exists.
  2. Safety Notice is reachable from it (showSafetyDisclaimer = true).
  3. At least one doc/scope link (README / Lean CNC Scope) is present.
  4. The safety sheet is still wired in ContentView (Safety reachable from
     the UI, not just the menu).

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
    content = (ROOT / "Sources" / "ShopPilot" / "ContentView.swift").read_text(encoding="utf-8")

    # 1. Help menu exists (replaces the default).
    must("CommandGroup(replacing: .help)" in app,
         "App.swift has a Help CommandGroup")

    # 2. Safety reachable.
    must('Button("Safety Notice")' in app and "session.showSafetyDisclaimer = true" in app,
         "Help menu has Safety Notice → showSafetyDisclaimer")

    # 3. Doc links.
    must("ShopPilot README" in app and "Lean CNC Scope" in app,
         "Help menu has README + Lean CNC Scope links")

    # 4. Safety sheet still wired in the UI.
    must("session.showSafetyDisclaimer" in content and ".sheet" in content,
         "ContentView still presents the safety sheet")

    if FAILURES:
        print("1605: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1605: PASS — Help menu exists; Safety reachable (menu + sheet)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

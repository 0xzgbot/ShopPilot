#!/usr/bin/env python3
"""SPK-1601 verify — File New Job replaces the session.

Asserts, by reading sources:
  1. AppSession.newJob() exists and calls replaceJob (a blank Untitled Job
     replaces the document — shapes/toolpaths/tree cleared) and lands on
     Setup.
  2. handleCommand(.newJob) calls newJob() — the command palette path is
     NOT stage-only.
  3. App.swift File menu "New Job" calls session.newJob() (⌘N does the same
     replace), not a bare stage switch.
  4. Dirty documents get a confirm-discard alert (NSAlert) before replace.

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
    session = (ROOT / "Sources" / "ShopPilot" / "AppSession.swift").read_text(encoding="utf-8")
    app = (ROOT / "Sources" / "ShopPilot" / "App.swift").read_text(encoding="utf-8")

    # 1. newJob() replaces the session via replaceJob + lands on Setup.
    must("func newJob() -> Bool" in session,
         "AppSession.newJob() exists")
    must("replaceJob(Job(name: \"Untitled Project\"))" in session,
         "newJob replaces with a blank Untitled Project")
    must('selectedStage = .setup' in session,
         "newJob lands on Setup (after replaceJob)")
    must("startAutosaverForCurrentJob()" in session,
         "replaceJob keeps autosave wiring (unchanged)")

    # 2. .newJob command routes to newJob() — not stage-only.
    must("case .newJob:" in session and "newJob()" in session,
         "handleCommand(.newJob) calls newJob() (not stage-only)")

    # 3. File menu New Job calls session.newJob().
    must('Button("New Job")' in app and "session.newJob()" in app,
         "App.swift File New Job calls session.newJob()")

    # 4. Dirty confirm alert.
    must("Discard unsaved changes?" in session and "NSAlert()" in session,
         "dirty documents get a confirm-discard alert")
    must("guard alert.runModal() == .alertFirstButtonReturn else { return false }" in session,
         "cancel aborts the replace")

    if FAILURES:
        print("1601: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1601: PASS — File New Job replaces session (blank Untitled + Setup; dirty confirm; palette + menu same path)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

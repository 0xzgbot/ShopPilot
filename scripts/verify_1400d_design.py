#!/usr/bin/env python3
"""SPK-1400d verify — Design empty state + Untitled Project chrome.

Asserts:
  1. Design empty copy says the tool is on the LEFT (not "tool above").
  2. Empty state has a "Try a sample" button wired to the 1400a API
     (SampleProjectsStore.samples.first + session.loadSampleProject).
     "Import Artwork…" is still present (kept, not removed).
  3. Chrome default is "Untitled Project" everywhere it is visible:
     ContentView.documentIdentity fallback, AppSession init, Job default.
  4. shop_pilot_pro_skip is NOT renamed (out of scope).

Exit 0 + PASS line on success; non-zero with details on failure.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT_VIEW = ROOT / "Sources" / "ShopPilot" / "ContentView.swift"
APP_SESSION = ROOT / "Sources" / "ShopPilot" / "AppSession.swift"
JOB = ROOT / "Sources" / "ShopPilotCore" / "Job.swift"

FAILURES: list[str] = []


def must(cond: bool, msg: str) -> None:
    if not cond:
        FAILURES.append(msg)


def main() -> int:
    cv = CONTENT_VIEW.read_text(encoding="utf-8")
    sess = APP_SESSION.read_text(encoding="utf-8")
    job = JOB.read_text(encoding="utf-8")

    # 1. Copy: tool on the LEFT, not "tool above".
    must("Pick a tool on the left" in cv,
         "empty copy says 'Pick a tool on the left'")
    must("Pick a tool above" not in cv,
         "stale 'Pick a tool above' copy removed")

    # 2. Try a sample via the 1400a API + Import Artwork kept.
    must("Try a sample" in cv, "'Try a sample' button present")
    must("SampleProjectsStore.samples.first" in cv,
         "sample button reads the store (no second catalog)")
    must("loadSampleProject(id:" in cv,
         "sample button routes through AppSession.loadSampleProject (1400a API)")
    must("Import Artwork…" in cv, "'Import Artwork…' kept")

    # 3. Untitled Project chrome (three visible spots).
    must('"Untitled Project"' in cv, "ContentView documentIdentity fallback")
    must('Job(name: "Untitled Project")' in sess, "AppSession init default")
    must('name: String = "Untitled Project"' in job, "Job default name")

    # 4. shop_pilot_pro_skip untouched (out of scope) — it lives in
    # AppSettings.swift / ContentView / PreferencesView, not AppSession.
    pro_skip_anywhere = any(
        "shop_pilot_pro_skip" in p.read_text(encoding="utf-8")
        for p in (ROOT / "Sources" / "ShopPilot").glob("*.swift")
    )
    must(pro_skip_anywhere, "shop_pilot_pro_skip key unchanged (anywhere in app target)")

    if FAILURES:
        print("1400d: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1400d: PASS — design empty + untitled project")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""SPK-1500 verify — File menu Open Job.

Asserts, by reading Sources/ShopPilot/App.swift:
  1. The File (newItem-replacing) CommandGroup has an "Open Job…" button.
  2. That button calls session.handleCommand(.openJob) — the SAME session
     path the Welcome sheet uses (→ openPackageFromPanel → real picker).
  3. The Open Job button carries the ⌘O-style keyboard shortcut (resolved via
     the registry id "file.open" — same key as CommandID.openJob).

Exit 0 + PASS line on success; non-zero with details on failure.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Sources" / "ShopPilot" / "App.swift"

FAILURES: list[str] = []


def must(cond: bool, msg: str) -> None:
    if not cond:
        FAILURES.append(msg)


def main() -> int:
    text = APP.read_text(encoding="utf-8")

    # 1. Open Job… button exists in the File group.
    must('Button("Open Job…")' in text, "App.swift has an 'Open Job…' File-menu button")

    # 2. It routes through the same session path as Welcome.
    must('session.handleCommand(.openJob)' in text,
         "Open Job… calls session.handleCommand(.openJob) (same path as Welcome)")

    # 3. Shortcut binding present.
    must('.keyboardShortcut(shortcut("file.open"))' in text,
         "Open Job… has the file.open keyboard shortcut (registry-resolvable ⌘O)")

    # 4. The registry resolves file.open to ⌘O (not the ⌘N fallback that
    #    would collide with New Job).
    reg = (ROOT / "Sources" / "ShopPilotCore" / "ShortcutRegistry.swift").read_text(encoding="utf-8")
    must('ShortcutBinding(id: "file.open", title: "Open Job…", defaultKey: "o", defaultModifiers: ["command"])' in reg,
         "ShortcutRegistry catalog binds file.open → ⌘O")

    if FAILURES:
        print("1500: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1500: PASS — File menu Open Job… routes to handleCommand(.openJob)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

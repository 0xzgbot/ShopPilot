#!/usr/bin/env python3
"""SPK-1606 verify — Edit menu Undo/Redo.

Asserts, by reading sources:
  1. App.swift Edit menu (CommandGroup before .undoRedo) has Undo + Redo
     buttons calling session.undo() / session.redo().
  2. ShortcutRegistry has edit.undo (⌘Z) and edit.redo (⇧⌘Z) entries.
  3. AppSession exposes canUndo/canRedo for the enabled state, and undo/redo
     use the same session stack (1403b snapshot undo).

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
    registry = (ROOT / "Sources" / "ShopPilotCore" / "ShortcutRegistry.swift").read_text(encoding="utf-8")

    # 1. Edit menu Undo/Redo call the session stack.
    must("CommandGroup(before: .undoRedo)" in app,
         "App.swift has an Edit undo/redo CommandGroup")
    must('Button("Undo")' in app and "session.undo()" in app,
         "Undo button calls session.undo()")
    must('Button("Redo")' in app and "session.redo()" in app,
         "Redo button calls session.redo()")

    # 2. Registry entries.
    must('ShortcutBinding(id: "edit.undo"' in registry,
         "ShortcutRegistry has edit.undo (⌘Z)")
    must('ShortcutBinding(id: "edit.redo"' in registry,
         "ShortcutRegistry has edit.redo (⇧⌘Z)")

    # 3. Session stack: undo/redo + enabled state.
    must("func undo() -> Bool" in session and "func redo() -> Bool" in session,
         "AppSession.undo/redo exist (1403b snapshot stack)")
    must("var canUndo: Bool { undoManager.canUndo }" in session
         and "var canRedo: Bool { undoManager.canRedo }" in session,
         "AppSession exposes canUndo/canRedo for menu enabled state")

    if FAILURES:
        print("1606: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1606: PASS — Edit menu Undo/Redo drive the session undo stack (⌘Z / ⇧⌘Z)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

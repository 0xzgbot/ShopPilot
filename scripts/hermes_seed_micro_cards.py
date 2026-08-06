#!/usr/bin/env python3
"""Park epic Hermes cards and seed a realistic micro Ready queue for Spark/Qwen."""

from __future__ import annotations

import json
import re
import sqlite3
import subprocess
import time
from pathlib import Path

BOARD = "shoppilot"
DB = Path.home() / ".hermes/kanban/boards/shoppilot/kanban.db"
ROOT = Path("/Users/zgbot/Desktop/ShopPilot")
PROMPT = ROOT / "docs/planning/KANBAN_MICRO_CARD_PROMPT.md"

PROTOCOL = f"""
See also: {PROMPT}

## Protocol
1. End with kanban_complete(...) or kanban_block(reason=...).
2. Only this micro card — no scope expansion.
3. Worktree only. Assignee coder.
4. No Phase H–K until SPK-0623 [x].
5. Simulator-first for machine. No third-party proprietary/CRV reverse-eng.
""".strip()


def hermes(*args: str) -> tuple[int, str]:
    p = subprocess.run(
        ["hermes", "kanban", "--board", BOARD, *args],
        text=True,
        capture_output=True,
    )
    return p.returncode, ((p.stdout or "") + (p.stderr or "")).strip()


def reclaim_running() -> None:
    conn = sqlite3.connect(str(DB))
    ids = [r[0] for r in conn.execute("SELECT id FROM tasks WHERE status='running'")]
    conn.close()
    for tid in ids:
        hermes("reclaim", tid, "--reason", "operator: rebuild micro-card board")


def park_all_active() -> int:
    """Schedule everything that isn't done/archived/human-blocked ship gate."""
    now = int(time.time())
    conn = sqlite3.connect(str(DB))
    conn.row_factory = sqlite3.Row
    n = 0
    for t in conn.execute("SELECT id, title, status FROM tasks"):
        if t["status"] in ("done", "archived"):
            continue
        if t["status"] == "blocked" and "0623" in (t["title"] or ""):
            continue
        conn.execute(
            """UPDATE tasks SET status='scheduled', priority=0, claim_lock=NULL,
               claim_expires=NULL, worker_pid=NULL, current_run_id=NULL,
               block_kind=NULL, consecutive_failures=0, goal_mode=0
             WHERE id=?""",
            (t["id"],),
        )
        conn.execute(
            "INSERT INTO task_events(task_id, kind, payload, created_at) VALUES (?,?,?,?)",
            (
                t["id"],
                "scheduled",
                json.dumps({"reason": "superseded by 2026-08-01 micro-card rebuild"}),
                now,
            ),
        )
        n += 1
    conn.commit()
    conn.close()
    return n


MICROS = [
    # Track 1 / spine slices
    (1000, "SPK-1100a AppSession owns job/layers/vectors/toolpaths/selection/dirty", """Parent: SPK-1100
AC:
- One session type owns job, layers, vectors, toolpaths, selection, dirty flag
- Stages can read that session (compile-time wiring or existing bindings)
Out of scope: save UI, browser redesign, inspector redesign, undo polish
Verify: swift build; smoke test or assert dirty flips on mutation"""),
    (990, "SPK-1100b .shoppilot save/open round-trip vectors+toolpaths", """Parent: SPK-1100 / SPK-0104
AC:
- Save package writes vectors+toolpaths (+ vars if present)
- Open restores them
Out of scope: autosave UX, crash recovery UI
Verify: one XCTest or scripted round-trip fixture"""),
    (980, "SPK-1100c Browser shows live layers from session", """Parent: SPK-1100 / SPK-0105
AC:
- Layers browser lists session layers and reflects add/remove/rename
Out of scope: components/toolpaths tabs polish, DnD
Verify: manual path noted in comment OR UI test hook"""),
    (970, "SPK-0403a StatusParser Idle/Run/Hold + MPos fixtures", """Parent: SPK-0403
AC:
- Parse <Idle|Run|Hold|...> with MPos X/Y/Z
- ≥3 XCTest fixtures
Out of scope: FS/buffer/Pn fields, UI
Verify: swift test --filter StatusParser (or named tests)"""),
    (960, "SPK-0404a GCodeStreamer ok-wait single line", """Parent: SPK-0404
AC:
- Send one line, wait for ok, advance index
- Unit test with sim/mock transport
Out of scope: hold/resume/reset, multi-line planner
Verify: swift test --filter GCodeStreamer (or named)"""),
    (950, "SPK-0406a Serial port enumerate list", """Parent: SPK-0406
AC:
- Enumerate candidate serial devices on macOS
- Returns stable identifiers for UI picker
Out of scope: open/read/write, IOKit edge cases
Verify: unit test with mocked enumerator OR dry-run API"""),
    (940, "SPK-0203a Offset engine golden for simple closed poly", """Parent: SPK-0203
AC:
- Offset one closed polyline by known delta
- Golden or XCTest asserts vertex count/bounds
Out of scope: UI button, boolean, open paths
Verify: swift test --filter Offset (or named)"""),
    (930, "SPK-0301a ToolDatabase endmill + V-bit JSON round-trip", """Parent: SPK-0301
AC:
- Models for endmill + V-bit with diameter/angle
- JSON load/save round-trip test
Out of scope: picker UI, cloud catalog
Verify: XCTest round-trip two tools"""),
    (920, "SPK-1162a README capability honesty paragraph", """Parent: SPK-1162
AC:
- README states what works today vs stub (sim-first, no false production-ready)
- Links SAFETY.md
Out of scope: full ship checklist, notarization
Verify: README section exists; no contradictory 'complete reference' claim"""),
    (910, "SPK-1161a One XCTest target runs a trivial assert", """Parent: SPK-1161 / SPK-1105
AC:
- `swift test` runs at least one ShopPilotTests case successfully on this machine OR documents Xcode-only blocker honestly in card result
Out of scope: full suite green, CI cloud
Verify: swift test output attached in kanban_complete summary"""),
    (900, "SPK-0107a ⌘K palette opens with 3 stub commands", """Parent: SPK-0107
AC:
- Command palette UI opens via shortcut/menu
- Lists ≥3 stub commands that no-op or route to existing actions
Out of scope: full command registry, fuzzy rank
Verify: build + note how to open palette"""),
    (890, "SPK-0404b Streamer hold/resume/reset realtime bytes", """Parent: SPK-0404
AC:
- Hold (!) / resume (~) / reset (0x18) APIs on streamer/session
- Unit test asserts bytes written to mock transport
Out of scope: UI chrome, large file stress
Verify: XCTest for realtime commands"""),
    (880, "SPK-0204a Boolean subtract one rectangle from another", """Parent: SPK-0204
AC:
- Subtract two axis-aligned rect polys; returns valid polygon(s)
- One XCTest/golden
Out of scope: UI, weld UI, self-intersect doctor
Verify: swift test --filter Boolean (or named)"""),
    (870, "SPK-0411a Stream fixture file with progress fraction", """Parent: SPK-0411
AC:
- Load a small fixture .nc and stream via sim transport with progress 0→1
Out of scope: UI freeze stress 10k lines, serial hardware
Verify: integration test or scripted sim stream completes"""),
    (860, "SPK-0500a Text object stores string + system font name", """Parent: SPK-0500
AC:
- Text model with string + fontName; renders or converts to path stub OK
Out of scope: text-on-curve, engraving packs
Verify: build + unit test create text model"""),
    (850, "SPK-0313a GRBL post writes .nc with safe header", """Parent: SPK-0313
AC:
- Post one trivial toolpath/path to .nc with units/header comment
Out of scope: all strategies, extension labeling UI
Verify: golden or file contains G21/G90-style preamble as designed"""),
]


def create_micros() -> list[str]:
    created = []
    for pri, title, ac in MICROS:
        key = "shoppilot-micro-" + re.sub(r"[^A-Za-z0-9]+", "-", title.split(" ", 1)[0])
        body = f"""Project: {ROOT}
Master: {ROOT}/MASTER_KANBAN.md
Finish: {ROOT}/docs/planning/FINISH_ROADMAP.md
Sizing: {PROMPT}

{ac}

{PROTOCOL}
"""
        rc, out = hermes(
            "create",
            title,
            "--body",
            body,
            "--assignee",
            "coder",
            "--project",
            "shoppilot",
            "--workspace",
            "worktree",
            "--priority",
            str(pri),
            "--max-runtime",
            "45m",
            "--max-retries",
            "2",
            "--idempotency-key",
            key,
            "--json",
        )
        created.append(f"{title} rc={rc} {out[:120]}")
    return created


def boost_ready_micros() -> None:
    conn = sqlite3.connect(str(DB))
    # Ensure newly created micros are ready with priorities; leave everything else scheduled
    for pri, title, _ in MICROS:
        spk = title.split(" ", 1)[0]
        conn.execute(
            """UPDATE tasks SET status='ready', assignee='coder', priority=?,
                   goal_mode=0, max_runtime_seconds=2700,
                   consecutive_failures=0, last_failure_error=NULL,
                   claim_lock=NULL, claim_expires=NULL, worker_pid=NULL,
                   current_run_id=NULL, block_kind=NULL
                 WHERE title LIKE ? AND status!='done'""",
            (pri, spk + "%"),
        )
    conn.commit()
    # Demote any ready that isn't one of our micros
    prefixes = tuple(t.split(" ", 1)[0] for _, t, _ in MICROS)
    for row in conn.execute("SELECT id, title FROM tasks WHERE status='ready'"):
        title = row[1] or ""
        if not any(title.startswith(p) for p in prefixes):
            conn.execute(
                "UPDATE tasks SET status='scheduled', priority=0 WHERE id=?",
                (row[0],),
            )
    conn.commit()
    conn.close()


def main() -> None:
    print("reclaim…")
    reclaim_running()
    print("park…")
    n = park_all_active()
    print(f"parked {n}")
    print("create micros…")
    for line in create_micros():
        print(" ", line)
    print("boost ready…")
    boost_ready_micros()
    conn = sqlite3.connect(str(DB))
    print("counts", dict(conn.execute("SELECT status,count(*) FROM tasks GROUP BY status")))
    print("READY:")
    for r in conn.execute(
        "SELECT priority, substr(title,1,70) FROM tasks WHERE status='ready' ORDER BY priority DESC"
    ):
        print(f"  [{r[0]}] {r[1]}")
    conn.close()


if __name__ == "__main__":
    main()

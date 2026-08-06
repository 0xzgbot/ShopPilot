#!/usr/bin/env python3
"""Realign shoppilot Hermes board for 8 non-overlapping coder workers."""

from __future__ import annotations

import json
import re
import sqlite3
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

BOARD = "shoppilot"
DB = Path.home() / ".hermes/kanban/boards/shoppilot/kanban.db"
MK = Path("/Users/zgbot/Desktop/ShopPilot/MASTER_KANBAN.md")
ROOT = Path("/Users/zgbot/Desktop/ShopPilot")

PROTOCOL = """
## CRITICAL WORKER PROTOCOL
1. End EVERY run with exactly one of: kanban_complete(...) OR kanban_block(reason=...).
2. Never exit cleanly without that call — it is a protocol violation.
3. DoD: Engine + UI + Persist + Verify. `swift build` alone is never enough.
4. Update MASTER_KANBAN.md checkbox + Work log before kanban_complete.
5. Implement ONLY this card. Do not start SPK-07xx+ until SPK-0623 is [x].
6. Use this task's worktree workspace; do not edit the main checkout if on a worktree.
7. Simulator-first for machine work. No third-party proprietary / CRV reverse-engineering.
8. If blocked on a human, kanban_block with a clear reason and stop.
""".strip()

# First wave: orthogonal lanes (different packages / surface area)
WAVE8 = [
    ("1100", 200, "PLAT AppSession spine"),
    ("0403", 190, "MACH StatusParser tests"),
    ("0404", 185, "MACH GCodeStreamer tests"),
    ("0406", 180, "MACH serial enumerate"),
    ("1161", 175, "QA XCTest scaffold"),
    ("1162", 170, "REL README/SHIP honesty"),
    ("0317", 165, "QA golden G-code fixtures"),
    ("0210", 160, "QA golden offset/boolean"),
]


def run(cmd: list[str]) -> tuple[int, str]:
    p = subprocess.run(cmd, text=True, capture_output=True)
    return p.returncode, ((p.stdout or "") + (p.stderr or "")).strip()


def hermes(*args: str) -> tuple[int, str]:
    return run(["hermes", "kanban", "--board", BOARD, *args])


def load_tasks() -> list[dict]:
    code, out = hermes("list", "--json")
    if code != 0:
        raise SystemExit(f"list failed: {out}")
    return json.loads(out)


def by_spk(tasks: list[dict]) -> dict[str, dict]:
    out = {}
    for t in tasks:
        m = re.search(r"SPK-(\d+)", t["title"])
        if m:
            out[m.group(1)] = t
    return out


def parse_md() -> dict[str, str]:
    md = {}
    for m in re.finditer(r"^- \[([ x!~-])\] \*\*SPK-(\d+)\*\*", MK.read_text(), re.M):
        md[m.group(2)] = m.group(1)
    return md


def ensure_ready(tid: str, reason: str) -> None:
    # promote from todo/blocked/scheduled if needed
    hermes("unblock", tid, "--reason", reason)
    hermes("promote", tid, "--force", reason)


def main() -> int:
    stats: dict[str, list] = defaultdict(list)
    md = parse_md()
    tasks = load_tasks()
    spk = by_spk(tasks)

    # --- 1) Complete markdown-[x] cards ---
    for num, mark in md.items():
        if mark != "x":
            continue
        t = spk.get(num)
        if not t or t["status"] == "done":
            continue
        tid = t["id"]
        if t["status"] in ("todo", "blocked", "scheduled"):
            rc, o = hermes("promote", tid, "--force", "sync: already [x] in MASTER_KANBAN")
            if rc != 0:
                stats["promote_fail"].append((tid, o[:120]))
                continue
        rc, o = hermes(
            "complete",
            tid,
            "--result",
            f"Synced: already [x] in MASTER_KANBAN.md (SPK-{num})",
        )
        if rc == 0:
            stats["completed"].append(f"SPK-{num}")
        else:
            stats["complete_fail"].append((tid, o[:160]))

    tasks = load_tasks()
    spk = by_spk(tasks)

    # --- 2) Schedule human blockers ---
    for t in tasks:
        m = re.search(r"SPK-(\d+)", t["title"])
        num = m.group(1) if m else None
        is_human = (num and md.get(num) == "!") or ("Human" in t["title"])
        if not is_human or t["status"] in ("scheduled", "done", "archived"):
            continue
        rc, o = hermes("schedule", t["id"], "Human-only — do not auto-dispatch")
        stats["scheduled_human" if rc == 0 else "schedule_fail"].append(
            t["id"] if rc == 0 else (t["id"], o[:120])
        )

    tasks = load_tasks()
    spk = by_spk(tasks)

    # --- 3) Park Phase H–K (0700–1010) until SPK-0623 ---
    park_ids = []
    for t in tasks:
        m = re.search(r"SPK-(\d+)", t["title"])
        if not m:
            continue
        n = int(m.group(1))
        if not (700 <= n <= 1010):
            continue
        if t["status"] in ("scheduled", "done", "archived"):
            continue
        if md.get(m.group(1)) == "!" or "Human" in t["title"]:
            continue
        park_ids.append(t["id"])
    # bulk schedule in chunks
    for i in range(0, len(park_ids), 20):
        chunk = park_ids[i : i + 20]
        rc, o = hermes(
            "schedule",
            chunk[0],
            "--ids",
            *chunk[1:],
            "Parked until SPK-0623 per FINISH_ROADMAP",
        )
        if rc == 0:
            stats["parked_hk"].extend(chunk)
        else:
            # fallback one-by-one
            for tid in chunk:
                rc2, o2 = hermes(
                    "schedule", tid, "Parked until SPK-0623 per FINISH_ROADMAP"
                )
                if rc2 == 0:
                    stats["parked_hk"].append(tid)
                else:
                    stats["park_fail"].append((tid, o2[:120]))

    tasks = load_tasks()
    spk = by_spk(tasks)

    # --- 4) Demote premature UI slices that need 1100 (1120–1139) ---
    t1100 = spk.get("1100")
    for t in tasks:
        m = re.search(r"SPK-(11[23]\d)", t["title"])
        if not m or t["status"] not in ("ready", "running", "todo", "blocked"):
            continue
        if t["status"] == "ready":
            rc, o = hermes(
                "block",
                t["id"],
                "--kind",
                "dependency",
                "Depends on SPK-1100 document session spine",
            )
            stats["blocked_premature" if rc == 0 else "block_fail"].append(
                t["id"] if rc == 0 else (t["id"], o[:120])
            )
        if t1100:
            hermes("link", t1100["id"], t["id"])

    tasks = load_tasks()
    spk = by_spk(tasks)

    # --- 5) Park anything else currently ready that is not in WAVE8 ---
    wave_nums = {n for n, _, _ in WAVE8}
    for t in tasks:
        if t["status"] != "ready":
            continue
        m = re.search(r"SPK-(\d+)", t["title"])
        num = m.group(1) if m else None
        if num in wave_nums:
            continue
        rc, o = hermes(
            "schedule",
            t["id"],
            "Not in current non-overlapping wave — parked",
        )
        stats["parked_nonwave" if rc == 0 else "park_fail"].append(
            t["id"] if rc == 0 else (t["id"], o[:120])
        )

    tasks = load_tasks()
    spk = by_spk(tasks)

    # --- 6) Promote WAVE8 to ready with worktrees + protocol + priority ---
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    promoted = []
    for num, priority, label in WAVE8:
        t = spk.get(num)
        if not t:
            stats["wave_missing"].append(num)
            continue
        if t["status"] == "done":
            stats["wave_already_done"].append(num)
            continue
        tid = t["id"]
        if t["status"] != "ready":
            # leave scheduled/blocked → promote
            if t["status"] == "scheduled":
                hermes("unblock", tid, "--reason", f"wave8: {label}")
            rc, o = hermes("promote", tid, "--force", f"wave8 non-overlap: {label}")
            if rc != 0:
                stats["wave_promote_fail"].append((num, o[:160]))
                continue
        # strengthen body / workspace / priority / goal mode via SQL
        wt = ROOT / ".worktrees" / tid
        body = (
            f"# SPK-{num} — {label}\n"
            f"**Project:** {ROOT}\n"
            f"**Master board:** {MK}\n"
            f"**Finish order:** docs/planning/FINISH_ROADMAP.md\n\n"
            f"## Card\nImplement SPK-{num} acceptance criteria from MASTER_KANBAN.md.\n\n"
            f"{PROTOCOL}\n"
        )
        conn.execute(
            """
            UPDATE tasks
               SET priority = ?,
                   assignee = 'coder',
                   workspace_kind = 'worktree',
                   workspace_path = ?,
                   branch_name = ?,
                   consecutive_failures = 0,
                   last_failure_error = NULL,
                   goal_mode = 1,
                   goal_max_turns = 30,
                   max_runtime_seconds = 7200,
                   body = ?,
                   status = 'ready',
                   claim_lock = NULL,
                   claim_expires = NULL,
                   worker_pid = NULL,
                   current_run_id = NULL,
                   block_kind = NULL
             WHERE id = ?
            """,
            (
                priority,
                str(wt),
                f"spk/{num}-{tid}",
                body,
                tid,
            ),
        )
        hermes("comment", tid, f"OPERATOR: wave8 lane ready — {label}. Worktree isolated. Goal mode on.")
        promoted.append(f"SPK-{num} ({tid})")
        stats["wave_ready"].append(f"SPK-{num}")

    conn.commit()
    conn.close()

    # --- summary ---
    tasks = load_tasks()
    counts = defaultdict(int)
    for t in tasks:
        counts[t["status"]] += 1
    ready = [t for t in tasks if t["status"] == "ready"]
    ready.sort(key=lambda t: (-(t.get("priority") or 0), t["title"]))

    print("=== REALIGN COMPLETE ===")
    for k in sorted(stats):
        print(f"{k}: {len(stats[k])}")
        for item in stats[k][:8]:
            print(f"  - {item}")
        if len(stats[k]) > 8:
            print(f"  ... +{len(stats[k]) - 8} more")
    print("\nBoard counts:", dict(counts))
    print(f"\nReady queue ({len(ready)}):")
    for t in ready:
        print(f"  [{t.get('priority', 0)}] {t['id']}  {t['title'][:80]}")
    print(f"\nWave promoted: {len(promoted)}")
    for p in promoted:
        print(f"  {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env bash
# Refill Hermes shoppilot Ready queue when it drains.
# Hermes does NOT auto-promote MASTER_KANBAN epics → Ready micros.
# Run periodically or after a wave of completions:
#   ./scripts/hermes_refill_ready.sh
#
# Optional: HERMES_REFILL_SEED=1 also creates a small emergency micro batch.

set -euo pipefail

BOARD="${HERMES_BOARD:-shoppilot}"
ROOT="${SHOPPILOT_ROOT:-$HOME/Desktop/ShopPilot}"

hermes kanban boards switch "$BOARD" >/dev/null

python3 - <<'PY'
import sqlite3, json, time, os
from pathlib import Path

db = Path.home() / ".hermes/kanban/boards" / os.environ.get("HERMES_BOARD", "shoppilot") / "kanban.db"
con = sqlite3.connect(db)
now = int(time.time())

def counts(assignee):
    r = con.execute("SELECT count(*) FROM tasks WHERE assignee=? AND status='ready'", (assignee,)).fetchone()[0]
    n = con.execute("SELECT count(*) FROM tasks WHERE assignee=? AND status='running'", (assignee,)).fetchone()[0]
    return r, n

# Unblock non-ship runtime/protocol failures so they can retry
unblocked = []
for tid, title in con.execute(
    "SELECT id, title FROM tasks WHERE status='blocked' AND title NOT LIKE '%0623%'"
):
    con.execute(
        """UPDATE tasks SET status='ready', consecutive_failures=0, last_failure_error=NULL,
               max_runtime_seconds=COALESCE(max_runtime_seconds, 5400),
               claim_lock=NULL, claim_expires=NULL, worker_pid=NULL, block_kind=NULL
         WHERE id=?""",
        (tid,),
    )
    con.execute(
        "INSERT INTO task_events(task_id,kind,payload,created_at) VALUES (?,?,?,?)",
        (tid, "promoted", json.dumps({"reason": "hermes_refill_ready: unblock non-ship"}), now),
    )
    unblocked.append(f"{tid}:{title[:40]}")

con.commit()
cr, cn = counts("coder")
sr, sn = counts("spark")
print(f"coder ready={cr} running={cn}")
print(f"spark ready={sr} running={sn}")
if unblocked:
    print("unblocked:", ", ".join(unblocked))
# Exit hint for shell: need seed if either lane has <3 ready
need = 1 if (cr < 3 or sr < 3) else 0
Path("/tmp/hermes_refill_need_seed").write_text(str(need))
PY

hermes kanban --board "$BOARD" dispatch 2>&1 | tail -20

echo "----"
hermes kanban --board "$BOARD" stats 2>&1 | head -20
echo "Ready:"
hermes kanban --board "$BOARD" list --status ready 2>&1 | head -40

if [[ "${HERMES_REFILL_SEED:-0}" == "1" ]] && [[ "$(cat /tmp/hermes_refill_need_seed 2>/dev/null || echo 0)" == "1" ]]; then
  echo "HERMES_REFILL_SEED=1 set but auto-seed templates live in Cursor ops — create micros via docs/planning/KANBAN_MICRO_CARD_PROMPT.md"
fi

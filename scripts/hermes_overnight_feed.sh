#!/usr/bin/env bash
# Overnight / unattended Ready feeder for ShopPilot Hermes board.
#
# Problem: Hermes never auto-promotes todo/scheduled epics into Ready micros.
# When Ready hits 0, DeepSeek (coder) idles even if the gateway is up.
#
# Policy (2026-08-03 trial):
#   - Medium DeepSeek slices (Engine+UI+Persist+Verify), not tiny feed spam
#   - Spark OFF by default (SPARK_READY_MIN=0) — Mac Swift lock is the bottleneck
#
# Usage (one-shot):
#   ./scripts/hermes_overnight_feed.sh
#
# Leave running while you sleep (checks every 30m):
#   nohup ./scripts/hermes_overnight_feed.sh --loop >> ~/Library/Logs/shoppilot-hermes-feed.log 2>&1 &
#
# Env knobs:
#   CODER_READY_MIN=4      seed when coder ready drops below this
#   CODER_SEED_BATCH=4     medium cards per top-up
#   SPARK_READY_MIN=0
#   SPARK_SEED_BATCH=0
#   LOOP_SECONDS=1800

set -euo pipefail

ROOT="${SHOPPILOT_ROOT:-$HOME/Desktop/ShopPilot}"
BOARD="${HERMES_BOARD:-shoppilot}"
CODER_READY_MIN="${CODER_READY_MIN:-4}"
CODER_SEED_BATCH="${CODER_SEED_BATCH:-4}"
SPARK_READY_MIN="${SPARK_READY_MIN:-0}"
SPARK_SEED_BATCH="${SPARK_SEED_BATCH:-0}"
LOOP_SECONDS="${LOOP_SECONDS:-1800}"
cd "$ROOT"

SPEED='
## SPEED RULES (mandatory)
- All swift via ./scripts/swift_locked.sh (or ./scripts/verify_locked.sh PRODUCT)
- Worktree only — never patch primary checkout Package.swift from a worktree task
- Never rm -rf .build; heartbeat while waiting on lock
- Prefer ShopPilotVerify* over swift test; no H–K before SPK-0623
See: docs/planning/HERMES_SWIFT_SPEED.md + docs/planning/FINISH_ROADMAP.md
Protocol: kanban_complete/block only; no scope creep.
'

# Medium vertical slices: Engine + UI/wiring + Persist + one Verify target (~45–90m).
# Format: title|parent|ac_block (use \n in ac via real newlines in string — keep single-line AC bullets here)
CODER_TEMPLATES=(
  'SPK-1101 Slice: nudge selection E+U+V|SPK-1101|Engine: nudge selected vectors by +1mm X in AppSession. UI: keyboard/button or menu item wired. Persist: selection+geometry survive save/open if session already persists vectors. Verify: ./scripts/verify_locked.sh ShopPilotVerify1101nudge (add executable if missing).'
  'SPK-1101 Slice: flip horizontal E+U+V|SPK-1101|Engine: mirror selected vectors across vertical centerline. UI: Flip H control. Persist round-trip if applicable. Verify: ./scripts/verify_locked.sh ShopPilotVerify1101flip.'
  'SPK-1102 Slice: profile on-path E+U+V|SPK-1102|Engine: profile on-path emits G1 for a closed rect fixture. UI: strategy toggle or param visible. Dirty when param changes. Verify: ./scripts/verify_locked.sh ShopPilotVerify1102profile.'
  'SPK-1102 Slice: dirty badge E+U+V|SPK-1102|Engine: editing a profile param marks toolpath node dirty. UI: dirty badge visible on node. Clear dirty after regenerate. Verify: ./scripts/verify_locked.sh ShopPilotVerify1102dirty.'
  'SPK-1103 Slice: preview empty+rapids E+U+V|SPK-1103|Engine/UI: empty-state copy when no gcode/vectors; rapids distinct color from cuts in wireframe. Verify: ./scripts/verify_locked.sh ShopPilotVerify1103preview.'
  'SPK-1104 Slice: load no-autorun + reset clears|SPK-1104|Safety: loading session gcode into machine buffer does not start stream. Reset realtime (0x18) clears alarm/error banner in sim. Verify: ./scripts/verify_locked.sh ShopPilotVerify1104safe.'
  'SPK-0313 Slice: GRBL safe header post|SPK-0313|Engine: GRBL post header includes G21/G90 and program comment. UI or export path uses it. Verify: ./scripts/verify_locked.sh ShopPilotVerify0313.'
  'SPK-0403 Slice: Alarm parse + banner|SPK-0403|Engine: StatusParser surfaces ALARM: without crash. UI: banner shows alarm text. Verify: ./scripts/verify_locked.sh ShopPilotVerify0403.'
  'SPK-0404 Slice: ok-wait streamer line|SPK-0404|Engine: streamer sends one line and waits for ok in sim. No next line until ok. Verify: ./scripts/verify_locked.sh ShopPilotVerify0404.'
  'SPK-0500 Slice: text object model+UI|SPK-0500|Engine: TextObject string+fontName Codable round-trip. UI: create/edit text in design surface or inspector. Verify: ./scripts/verify_locked.sh ShopPilotVerify0500.'
)

SPARK_TEMPLATES=(
  'SPK-0203 Feed: offset open poly |SPK-0203|Offset open polyline returns non-empty result'
)

count_ready() {
  local assignee="$1"
  python3 - <<PY
import sqlite3
from pathlib import Path
con = sqlite3.connect(Path.home() / ".hermes/kanban/boards/${BOARD}/kanban.db")
print(con.execute(
    "SELECT count(*) FROM tasks WHERE assignee=? AND status='ready'",
    ("${assignee}",),
).fetchone()[0])
PY
}

unblock_non_ship() {
  python3 - <<'PY'
import sqlite3, json, time
from pathlib import Path
import os
board = os.environ.get("HERMES_BOARD", "shoppilot")
con = sqlite3.connect(Path.home() / f".hermes/kanban/boards/{board}/kanban.db")
now = int(time.time())
n = 0
for tid, title in con.execute(
    "SELECT id, title FROM tasks WHERE status='blocked' AND title NOT LIKE '%0623%'"
):
    con.execute(
        """UPDATE tasks SET status='ready', consecutive_failures=0, last_failure_error=NULL,
               max_runtime_seconds=5400, claim_lock=NULL, worker_pid=NULL, block_kind=NULL
         WHERE id=?""",
        (tid,),
    )
    con.execute(
        "INSERT INTO task_events(task_id,kind,payload,created_at) VALUES (?,?,?,?)",
        (tid, "promoted", json.dumps({"reason": "overnight_feed unblock"}), now),
    )
    n += 1
con.commit()
print(f"unblocked={n}")
PY
}

create_one() {
  local assignee="$1"
  local raw="$2"
  local stamp
  stamp="$(date +%H%M%S)-$RANDOM"
  local title parent ac
  IFS='|' read -r title parent ac <<<"$raw"
  title="${title} [${stamp}]"
  hermes kanban create "$title" \
    --assignee "$assignee" \
    --workspace worktree \
    --project shoppilot \
    --max-runtime 90m \
    --priority 75 \
    --max-retries 3 \
    --created-by overnight-feed \
    --body "Parent: ${parent}
Card size: MEDIUM vertical slice (Engine + UI wiring + Persist if applicable + Verify). Not an epic; not a tiny one-liner.

AC:
- ${ac}

Out of scope: full parent epic; Phase H–K; unrelated toolpaths; rm -rf .build

Verify:
- Prefer ./scripts/verify_locked.sh ShopPilotVerifyXXXX named in AC (create executableTarget if missing)
- Do NOT bare swift test / full-package thrash

${SPEED}" \
    --json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print("created", d["id"], d["assignee"], d["title"][:70])' \
    || echo "create-failed: $title"
}

seed_assignee() {
  local assignee="$1"
  local need="$2"
  local batch="$3"
  shift 3
  local templates=("$@")
  local ready
  ready="$(count_ready "$assignee")"
  echo "${assignee}: ready=${ready} (min=${need})"
  if [[ "$need" -le 0 ]]; then
    echo "skip seed ${assignee} (min=0)"
    return 0
  fi
  if [[ "$ready" -ge "$need" ]]; then
    return 0
  fi
  if [[ ${#templates[@]} -eq 0 ]]; then
    echo "no templates for ${assignee}"
    return 0
  fi
  local to_make=$((need + batch - ready))
  if [[ "$to_make" -gt "$batch" ]]; then to_make="$batch"; fi
  echo "seeding ${to_make} medium cards for ${assignee}…"
  local i=0
  local n=${#templates[@]}
  while [[ "$i" -lt "$to_make" ]]; do
    create_one "$assignee" "${templates[$((i % n))]}"
    i=$((i + 1))
  done
}

park_spark_ready() {
  # Keep Spark from being dispatched while trial is DeepSeek-only.
  python3 - <<'PY'
import sqlite3, json, time, os
from pathlib import Path
board = os.environ.get("HERMES_BOARD", "shoppilot")
con = sqlite3.connect(Path.home() / f".hermes/kanban/boards/{board}/kanban.db")
now = int(time.time())
n = 0
for tid in con.execute("SELECT id FROM tasks WHERE assignee='spark' AND status='ready'"):
    con.execute(
        "UPDATE tasks SET status='scheduled', claim_lock=NULL, worker_pid=NULL WHERE id=?",
        (tid[0],),
    )
    con.execute(
        "INSERT INTO task_events(task_id,kind,payload,created_at) VALUES (?,?,?,?)",
        (tid[0], "parked", json.dumps({"reason": "spark off — medium DeepSeek trial"}), now),
    )
    n += 1
con.commit()
print(f"parked_spark_ready={n}")
PY
}

ensure_gateway() {
  if hermes gateway list 2>/dev/null | grep -q '✓ coder'; then
    echo "gateway: coder up"
  else
    echo "gateway: starting coder…"
    hermes -p coder gateway start 2>&1 || hermes -p coder gateway run --replace >/tmp/hermes-coder-gateway.log 2>&1 &
    sleep 3
  fi
}

once() {
  echo "==== $(date -Iseconds) overnight feed (medium DeepSeek / spark off) ===="
  hermes kanban boards switch "$BOARD" >/dev/null
  ensure_gateway
  unblock_non_ship
  park_spark_ready
  seed_assignee coder "$CODER_READY_MIN" "$CODER_SEED_BATCH" "${CODER_TEMPLATES[@]}"
  if [[ "$SPARK_READY_MIN" -gt 0 ]]; then
    seed_assignee spark "$SPARK_READY_MIN" "$SPARK_SEED_BATCH" "${SPARK_TEMPLATES[@]}"
  else
    echo "spark: seeding disabled (SPARK_READY_MIN=0)"
  fi
  hermes kanban --board "$BOARD" dispatch 2>&1 | tail -20
  hermes kanban --board "$BOARD" stats 2>&1 | head -18
  echo "coder_ready=$(count_ready coder) spark_ready=$(count_ready spark)"
}

if [[ "${1:-}" == "--loop" ]]; then
  while true; do
    once || true
    echo "sleeping ${LOOP_SECONDS}s…"
    sleep "$LOOP_SECONDS"
  done
else
  once
fi

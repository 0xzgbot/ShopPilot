#!/usr/bin/env bash
# Serialize all ShopPilot Swift invocations across Hermes worktrees.
# macOS has no util-linux flock — use Python fcntl.
#
# Usage (from repo or worktree root):
#   ./scripts/swift_locked.sh build --target ShopPilotCore
#   ./scripts/swift_locked.sh run ShopPilotVerify1103a
#   ./scripts/swift_locked.sh build --product ShopPilot
#
# Never wipe .build from workers. Never run bare `swift build` in parallel.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCK_FILE="${SHOPPILOT_SWIFT_LOCK:-${REPO_ROOT}/.swift.lock}"
WAIT_NOTE_SEC="${SHOPPILOT_SWIFT_LOCK_WAIT_NOTE:-30}"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <swift-args...>" >&2
  echo "example: $0 build --target ShopPilotCore" >&2
  exit 2
fi

# Refuse destructive patterns if someone passes them as args (belt + suspenders).
for arg in "$@"; do
  if [[ "$arg" == ".build" || "$arg" == *"/.build"* ]]; then
    echo "swift_locked: refusing args that look like a .build wipe: $*" >&2
    exit 2
  fi
done

export LOCK_FILE WAIT_NOTE_SEC
export SWIFT_ARGS_B64
SWIFT_ARGS_B64="$(printf '%s\0' "$@" | base64)"

python3 - <<'PY'
import base64, fcntl, os, sys, time, subprocess

lock_path = os.environ["LOCK_FILE"]
wait_note = float(os.environ.get("WAIT_NOTE_SEC", "30"))
raw = base64.b64decode(os.environ["SWIFT_ARGS_B64"])
args = [a.decode() for a in raw.split(b"\0") if a]

os.makedirs(os.path.dirname(lock_path) or ".", exist_ok=True)
# Ensure lock file exists
open(lock_path, "a").close()

fd = os.open(lock_path, os.O_RDWR)
start = time.time()
last_note = start
print(f"swift_locked: waiting for lock {lock_path} …", flush=True)

while True:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except BlockingIOError:
        now = time.time()
        if now - last_note >= wait_note:
            print(
                f"swift_locked: still waiting ({int(now - start)}s) — "
                "heartbeat and wait; do NOT start another swift build",
                flush=True,
            )
            last_note = now
        time.sleep(1.0)

waited = time.time() - start
print(
    f"swift_locked: acquired after {waited:.1f}s — running: swift {' '.join(args)}",
    flush=True,
)
try:
    proc = subprocess.run(["swift", *args])
    sys.exit(proc.returncode)
finally:
    fcntl.flock(fd, fcntl.LOCK_UN)
    os.close(fd)
    print("swift_locked: released", flush=True)
PY

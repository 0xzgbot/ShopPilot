# Moving ShopPilot to a new Mac

**Canonical remote:** `https://github.com/0xzgbot/ShopPilot.git`  
**Canonical branch:** `master` (after this migrate wave)

## On the new computer

```bash
# 1. Xcode Command Line Tools (or full Xcode)
xcode-select --install
swift --version

# 2. Clone once — do not copy 100+ Hermes worktrees
git clone https://github.com/0xzgbot/ShopPilot.git
cd ShopPilot
git checkout master
git pull

# 3. Warm build
./scripts/swift_locked.sh build --product ShopPilot
# optional: ./scripts/swift_locked.sh test

# 4. Hermes (optional) — fresh board is fine
# Truth is MASTER_KANBAN.md + docs/planning/FINISH_ROADMAP.md
# Recreate Ready medium slices from MASTER; do not restore old feed spam.
```

## What you do **not** need to copy

| Skip | Why |
| --- | --- |
| `.worktrees/` | Ephemeral Hermes checkouts; code is on `master` |
| Local `shoppilot/t_*` branches | Absorbed / obsolete |
| `~/.hermes/kanban/boards/shoppilot/kanban.db` | Dispatch queue only; MASTER is truth |
| Old `.build/` | Rebuild on the new machine |

## Optional: Hermes on the new Mac

1. Install Hermes + coder profile (Nous DeepSeek).  
2. `hermes kanban boards` → create/switch `shoppilot`, `default_workdir` = clone path.  
3. Seed a few medium P0 cards from `MASTER_KANBAN.md` / `scripts/hermes_overnight_feed.sh`.  
4. Prefer `SPARK_READY_MIN=0` until the new Mac is proven.

## Prefer a stronger Mac

16GB laptops thrash under parallel Swift. 32GB+ Apple Silicon is much happier for multi-agent verify.

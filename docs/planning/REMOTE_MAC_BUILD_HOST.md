# Remote Mac build host — setup (ShopPilot)

Goal: stop using the **laptop** as the Swift compile farm. Agents still edit ShopPilot; **builds/verifies run on a stronger Mac**.

ShopPilot is **SwiftUI macOS** — the builder must be a Mac with Command Line Tools (Xcode.app optional; CLT + `ShopPilotVerify*` is enough for Hermes).

---

## Recommended shape (simplest)

**Run Hermes + worktrees on the build Mac.** Laptop is only for you (Hermes UI / SSH / Screen Sharing).

```
┌──────────────┐         Tailscale / LAN          ┌─────────────────────┐
│ Your laptop  │ ───────────────────────────────► │ Build Mac (mini)    │
│ browse/SSH   │                                  │ git clone ShopPilot │
│ optional UI  │                                  │ hermes gateway      │
└──────────────┘                                  │ coder workers       │
                                                  │ .swift.lock + .build│
                                                  └─────────────────────┘
```

Why this beats “SSH only the compile step”: Hermes worktrees, file edits, and `swift_locked` already assume one machine. Moving the **whole worker** avoids rsync hell.

---

## Hardware

| Spec | Minimum | Comfortable |
| --- | --- | --- |
| Machine | Any Apple Silicon Mac | **Mac mini** M2/M4+ |
| RAM | 16 GB | **32 GB+** (Hermes worktrees + Swift) |
| Disk | 256 GB free for clones/`.build` | 512 GB+ |
| Network | Same LAN or **Tailscale** | Always-on, not sleep |

Put the mini on power; disable sleep while building (`caffeinate` or Energy Saver → prevent sleep).

---

## 1. Prepare the build Mac

1. Install macOS updates.
2. Install **Xcode Command Line Tools**:
   ```bash
   xcode-select --install
   swift --version
   ```
3. Install Homebrew (optional but useful), `git`, and your Hermes install the same way as the laptop.
4. Join **Tailscale** (same tailnet as the laptop / Spark box). Note the MagicDNS name or `100.x` IP.
5. Enable **Remote Login** (System Settings → General → Sharing → Remote Login) so you can SSH:
   ```bash
   ssh zgbot@build-mac   # or 100.x.x.x
   ```
6. Clone the repo once:
   ```bash
   mkdir -p ~/Desktop && cd ~/Desktop
   git clone git@github.com:0xzgbot/ShopPilot.git
   cd ShopPilot
   ./scripts/swift_locked.sh build --product ShopPilot   # warm .build once
   ```

---

## 2. Point Hermes at the build Mac

On the **build Mac**:

1. Install / copy your Hermes `coder` profile (or fresh install + same model keys).
2. Set the ShopPilot board `default_workdir` to the clone on **that** machine, e.g. `/Users/zgbot/Desktop/ShopPilot`.
3. Confirm kanban caps match the trial:
   - `coder` `max_in_progress_per_profile: 5` (or 4 if still thrashing)
   - `spark` `max_in_progress_per_profile: 0` until the mini is proven
4. Start gateway on the build Mac:
   ```bash
   hermes -p coder gateway start
   hermes gateway list
   ```
5. Start the overnight feed **on the build Mac** (not the laptop):
   ```bash
   nohup env CODER_READY_MIN=4 CODER_SEED_BATCH=4 SPARK_READY_MIN=0 \
     ./scripts/hermes_overnight_feed.sh --loop \
     >> ~/Library/Logs/shoppilot-hermes-feed.log 2>&1 &
   ```

On the **laptop**: stop the local feed loop and local gateway so two machines don’t double-dispatch the same board DB.

**Important:** Hermes kanban DB lives under `~/.hermes/…` **per machine**. Pick one host as the **only** dispatcher (the build Mac). Don’t run `dispatch` from both.

---

## 3. Day-to-day use from the laptop

- SSH: `ssh build-mac` then `hermes kanban --board shoppilot stats`
- Or Screen Sharing / Hermes Desktop connected to that host if you use it
- Edit docs / planning on either machine; **agent worktrees stay on the build Mac**
- Git: workers push from the build Mac; pull on the laptop when you want to review

---

## Alternative: laptop agents, remote compile only (harder)

Only if you must keep Hermes on the laptop:

1. Build Mac has a bare clone or receives `rsync` of each worktree before verify.
2. Wrap `scripts/swift_locked.sh` to:
   ```bash
   ssh build-mac "cd '$REMOTE_WT' && ./scripts/swift_locked.sh $*"
   ```
3. Sync Sources before every verify; sync nothing destructive back without care.

This is fragile (path mapping, lock location, partial sync). Prefer **Hermes-on-build-Mac** unless you invest in a real sync script.

---

## Sanity checks

```bash
# On build Mac
uptime
sysctl -n hw.memsize hw.ncpu
./scripts/verify_locked.sh ShopPilotVerify1103a   # or any existing verify
hermes kanban --board shoppilot stats
pgrep -fl 'work kanban task' | wc -l
```

Healthy: verifies finish without multi‑10‑minute lock waits; few/no `exit 124` in agent logs.

---

## Cost / buy order

1. **Mac mini 32GB** (biggest win vs 16GB laptop)  
2. Keep laptop for Cursor / chat / reviewing PRs  
3. Optional later: second mini only if one machine’s Swift lock is still the limiter after RAM upgrade  

Windows still cannot be the builder for this app.

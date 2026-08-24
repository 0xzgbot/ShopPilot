# ShopPilot — Build / Test Ground Truth

**Recorded:** 2026-08-24 (supersedes the 2026-08-11 record)
**Purpose:** empirical status — the authoritative gate is the CLT sweep, not build-only smoke.

## Toolchain

| Item | Value |
| --- | --- |
| Swift | Apple Swift 6.2 (`swift-driver`, Xcode toolchain, macOS 26.5 SDK) |
| `DEVELOPER_DIR` | `/Applications/Xcode.app/Contents/Developer` (full Xcode selected for builds) |
| Platform | macOS 14+ (arm64 + x86_64 universal release) |

## Results (2026-08-24)

| Check | Result |
| --- | --- |
| `./scripts/swift_locked.sh build` (whole package, ~1150 build steps / 460 targets) | **PASS** (531s cold-ish) |
| Full regression sweep (`run_overnight_shakedown.sh`) | **229 PASS / 2 FAIL → fixed same day / 0 WARN / 1 skipped** → `results/CLTS.md` |
| Post-fix state | both FAIL targets re-run **PASS** (`ShopPilotVerify1104a`, `ShopPilotVerify1317`) |
| Per-target gate | `./scripts/verify_locked.sh <Target>` — exit 0 + canonical `…: PASS` line |

### The two same-day failures (both stale verifies, not product bugs)

1. **ShopPilotVerify1104a** — counted raw wire bytes; SPK-1508's status poller
   legitimately interleaves a `?` query byte on short streams. Fixed to count
   command traffic only. Pre-existing at HEAD (fails with tree stashed).
2. **ShopPilotVerify1317** — froze `bindings.count == 11`; SPK-1600/1606/1610
   grew the shortcut catalog to 17. Fixed to assert against
   `ShortcutRegistry.catalog.count`. Pre-existing at HEAD.

Details on MASTER_KANBAN (SPK-SHAKE-BUG-* cards, closed 2026-08-24).

## How the gates work

1. The repo's test gate is **CLT executables** (`Sources/ShopPilotVerify*/main.swift`), not XCTest — each proves real engine behavior with `expect()` assertions and prints a canonical `ShopPilotVerifyNNNN: PASS — …` line.
2. `verify_locked.sh <Target>` builds + runs one target; `run_overnight_shakedown.sh` sweeps all of them serially and writes `results/CLTS.md`.
3. Targets that exit 0 **without** a PASS marker are flagged WARN (the sweep reports 0 WARN since 2026-08-11).
4. Never trust `tail -1` of a verify log — the last line can be `swift_locked: released`. Grep the full output for `PASS`/`FAIL`.

## How to launch

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/swift_locked.sh run ShopPilot
# Demoable path: Setup → Design (Add Rectangle) → Cut (Generate Profile) → Machine (Simulator → Start)
```

# ShopPilot — Build / Test Ground Truth

**Recorded:** 2026-08-11 (supersedes the 2026-08-01 CLI-only record)  
**Purpose:** empirical status — the authoritative gate is the CLT sweep, not build-only smoke.

## Toolchain

| Item | Value |
| --- | --- |
| Swift | Apple Swift 6.x (`swift-driver`, Xcode toolchain) |
| `DEVELOPER_DIR` | `/Applications/Xcode.app/Contents/Developer` (full Xcode selected for builds) |
| Platform | macOS 14+ (arm64 + x86_64 universal release) |

## Results (2026-08-11)

| Check | Result |
| --- | --- |
| `./scripts/swift_locked.sh build` (whole package) | **PASS** |
| Full regression sweep (`run_overnight_shakedown.sh`) | **175 PASS / 0 FAIL / 0 WARN / 1 skipped** → `results/CLTS.md` |
| Per-target gate | `./scripts/verify_locked.sh <Target>` — exit 0 + canonical `…: PASS` line |

## How the gates work

1. The repo's test gate is **CLT executables** (`Sources/ShopPilotVerify*/main.swift`), not XCTest — each proves real engine behavior with `expect()` assertions and prints a canonical `ShopPilotVerifyNNNN: PASS — …` line.
2. `verify_locked.sh <Target>` builds + runs one target; `run_overnight_shakedown.sh` sweeps all of them serially and writes `results/CLTS.md`.
3. Targets that exit 0 **without** a PASS marker are flagged WARN (fixed for all 15 offenders 2026-08-11 — SPK-1325 hygiene; the sweep now reports 0 WARN).
4. Never trust `tail -1` of a verify log — the last line can be `swift_locked: released`. Grep the full output for `PASS`/`FAIL`.

## How to launch

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift run ShopPilot
# Demoable path: Setup → Design (Add Rectangle) → Cut (Generate Profile) → Machine (Simulator → Start)
```

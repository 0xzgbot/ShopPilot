# ShopPilot — Build / Test Ground Truth

**Recorded:** 2026-08-01  
**Purpose:** Phase 0 of status gameplan — empirical status before UI wiring.

## Toolchain

| Item | Value |
| --- | --- |
| Swift | Apple Swift 6.3 (`swift-driver` 1.148.6) |
| `xcode-select -p` | `/Library/Developer/CommandLineTools` |
| Full Xcode | **Not selected** (XCTest unavailable) |

## Results

| Check | Result |
| --- | --- |
| `swift build` | **PASS** |
| `swift test` | **FAIL** — `error: no such module 'XCTest'` |
| `./scripts/verify_golden_path.sh` | **PASS** — profile G-code → simulator stream + pause/resume |

## Implications

1. Prior Kanban claims of “all Core unit tests green” are **not verifiable** on this machine with CLI tools alone.
2. `scripts/test.sh` correctly falls back to build-only smoke when XCTest is missing — that must **not** be treated as full test green.
3. To run the XCTest suite: install Xcode, then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` and re-run `swift test`.

## Plan / Kanban repair (2026-08-01)

- Finish roadmap: [`FINISH_ROADMAP.md`](./FINISH_ROADMAP.md) — Tracks 1–6, DoD = Engine+UI+Persist+Verify.
- Kanban: false v1 `[x]` reopened; H–K backlog; human `[!]`; spine cards SPK-1100–1106.
- Empty form-index CSV removed earlier.
- **Next implementation claim:** SPK-1100 (document session spine).

## How to launch

```bash
swift run ShopPilot
# Demoable path: Setup → Design (Add Rectangle) → Cut (Generate Profile) → Machine (Simulator → Start)
```

# Hermes Swift speed — Verify habit (CLT)

Use this on every ShopPilot micro card so workers stop thrashing the Mac.

## Default Verify AC

```text
Verify:
- ./scripts/verify_locked.sh ShopPilotVerifyXXXX
```

Equivalent:

```text
- ./scripts/swift_locked.sh run ShopPilotVerifyXXXX
```

Add a tiny executable under `Sources/ShopPilotVerifyXXXX/main.swift` + `Package.swift` `.executableTarget` when the card needs proof and XCTest is unavailable.

## Do / Don't

| Do | Don't |
| --- | --- |
| `./scripts/swift_locked.sh build --target OneTarget` | bare `swift build` |
| `./scripts/verify_locked.sh ShopPilotVerify*` | `swift test` (no Xcode.app/XCTest on CLT) |
| Wait + `kanban_heartbeat` on lock | Second parallel `swift` |
| Keep `.build` warm | `rm -rf .build` |

## Card body snippet (paste)

```text
Swift: only via ./scripts/swift_locked.sh (or verify_locked.sh). Never rm -rf .build.
Worktree-only Sources. Heartbeat while waiting on the Swift lock.
Verify: ./scripts/verify_locked.sh ShopPilotVerifyXXXX
```

## Throughput notes (this laptop)

- Bottleneck is **local Swift compile + 16GB RAM**, not DeepSeek/Spark GPUs.
- Prefer **medium DeepSeek slices**, **Spark off**, coder ≤5.
- A newer Mac (more RAM + cores, e.g. M-series 32GB+) helps a lot: parallel agents spend less time thrashing under memory pressure; the lock still serializes full builds, but each build finishes faster.
- **Windows cannot build/run this SwiftUI macOS app.** Agents may draft pure logic remotely, but compile + UI + verify must run on macOS (this Mac or a remote Mac builder).

See also: [KANBAN_MICRO_CARD_PROMPT.md](./KANBAN_MICRO_CARD_PROMPT.md), [HERMES_START_PROMPT.md](../../HERMES_START_PROMPT.md), [NEW_COMPUTER_MIGRATE.md](./NEW_COMPUTER_MIGRATE.md).

# StatusParser Verify Checklist — GRBL golden fixtures → assertions

**Date:** 2026-08-05 · **Input:** `GRBL_DIALECT_MATRIX.md` §1–§10. **Purpose:** map each golden fixture under `research/raw/grbl_golden/` to concrete assertions for the `ShopPilotVerify*` suite (StatusParser / GCodeStream). No StatusParser code changes here — this is the test contract for the build wave.
**Fixture location note:** golden files live under `research/raw/grbl_golden/` which is **gitignored** (research/raw policy). For CI reproducibility, the build wave should either (a) copy fixtures into `ShopPilotTests/Fixtures/` (checked in) or (b) regenerate from this checklist — decide at build time; the checklist is the source of truth either way.

## 1. Fixture inventory

| File | Content | Exists |
|---|---|---|
| `grbl_boot.txt` | boot, `$` help, alarm boot, $X unlock, $H, startup blocks, $SLP, reset-while-moving | ✅ |
| `grbl_status_types.txt` | all 9 states + sub-states, MPos/WPos, Bf/Ln/FS/WCO/Pn/Ov/A fields, $13 inches | ✅ |
| `grbl_settings_dollar.txt` | `$$` full dump, `$N`, `$#`, `$G`, `$I`, setting write | ✅ |
| `grbl_errors_alarms.txt` | error codes 1–38 sampler, ALARM 1–10, MSG feedback, echo, startup error | ✅ |
| `grbl_stream_session.txt` | realistic stream: $C check, hold/resume, jog, tool-change sync, M-codes | ✅ |
| `fluidnc_boot_status.txt` | FluidNC boot, 6-axis status, $H=XY, $ME/$MD, SD, macros, $$ | ✅ |

## 2. Assertions by fixture (parser-level)

Legend: `P0` = must pass for the parser to land; `P1` = hardening; `[!]` = needs live hardware to fully validate (spec-derived fixture may be wrong in the wild).

### grbl_boot.txt
| # | Assertion | Level | Notes |
|---|---|---|---|
| B1 | Welcome regex `^Grbl 1\.1[hd-f] \['\$' for help\]$` parses to version `1.1h` | P0 | keep version-tolerant: `Grbl\s+[\d.]+[a-z]?` |
| B2 | `[HLP:…]` line recognized as push message, not stream ack | P0 | must not count toward stream |
| B3 | `<Alarm\|MPos:0.000,0.000,0.000>` → state=alarm, MPos parsed, position retained | P0 | |
| B4 | `error:9` after g-code in alarm → error code 9 surfaced + stream halted | P0 | locked-out semantics |
| B5 | `[MSG:'$H'\|'$X' to unlock]` → unlock-hint surfaced in UI | P1 | |
| B6 | `$X` → `[MSG:Caution: Unlocked]` + `ok` ack; alarm cleared | P0 | |
| B7 | `>G54G21:ok` → startup-line execution parsed; `:ok` suffix NOT counted as stream ack | P0 | critical: 2-ack bug class |
| B8 | `$SLP` → `[MSG:Sleeping]`; sleep state expected on next `?` | P1 | |
| B9 | Reset-while-moving → `ALARM:3` + `[MSG:Reset to continue]`; UI must force re-home banner | P0 | FM-17 |

### grbl_status_types.txt
| # | Assertion | Level | Notes |
|---|---|---|---|
| S1 | All states parse: Idle, Run, Hold, Jog, Alarm, Door, Check, Home, Sleep | P0 | state enum must cover all 9 |
| S2 | Sub-states: `Hold:0/1`, `Door:0/1/2/3` parsed to (state, subState) | P0 | Hold:1 → reset throws alarm (UI warning) |
| S3 | `MPos:` vs `WPos:` both parsed; WCO equation `WPos = MPos − WCO` verified | P0 | parser must expose both even when only one transmitted |
| S4 | `Bf:15,128` → planner blocks avail + RX bytes avail | P1 | |
| S5 | `Ln:12345` → executing line number | P1 | |
| S6 | `FS:450.0,8000` → feed + spindle; `F:500` (no-spindle build) also parses | P0 | two variants |
| S7 | `WCO:0.000,1.551,5.664` → offset vector; appears intermittently (every 10/30 reports) | P0 | parser must tolerate absence |
| S8 | `Pn:PZ` / `Pn:XYZ` → triggered pin letters | P1 | |
| S9 | `Ov:100,100,100` + `A:SF` → overrides + accessory state (S/C/F/M letters) | P1 | |
| S10 | `$13=1` inches report: units flag flips MPos/FS interpretation | P1 | `[!]` verify against real inch-reporting board |

### grbl_settings_dollar.txt
| # | Assertion | Level | Notes |
|---|---|---|---|
| D1 | `$$` dump: 30+ `$x=val` lines parsed into settings map, terminated by `ok` | P0 | |
| D2 | `$N` startup lines parsed (`$N0=G54`); empty `$N1=` tolerated | P1 | |
| D3 | `$#` params: `[G54:…]`, `[G92:…]`, `[TLO:0.000]`, `[PRB:…:0/1]` parsed | P1 | probe success flag |
| D4 | `$G` → `[GC:…]` modal-state string parsed (G20/G21/G90/G94/M5/T0/S0/F500) | P1 | |
| D5 | `$I` → `[VER:…]` + `[OPT:…]`; custom string tolerated | P1 | |
| D6 | Setting write `$27=1.500` → `ok` ack; subsequent `$$` reflects new value | P1 | `[!]` EEPROM write timing on real board |

### grbl_errors_alarms.txt
| # | Assertion | Level | Notes |
|---|---|---|---|
| E1 | `error:1`…`error:38` numeric codes parsed; stream halts on any error | P0 | 38 codes; map to user text |
| E2 | `ALARM:1`…`ALARM:10` → distinct alarm enum + re-home/unlock UX | P0 | FM-16/17/19 |
| E3 | `[MSG:Reset to continue]` after hard/soft-limit alarm | P0 | |
| E4 | `[MSG:Check Door]` / `[MSG:Check Limits]` / `[MSG:Pgm End]` / `[MSG:Enabled|Disabled]` / `[MSG:Sleeping]` / `[MSG:Restoring defaults]` parsed, not stream acks | P1 | |
| E5 | `[echo:G1X0.540Y10.4F100]` tolerated (debug builds) | P1 | |
| E6 | `>G54G21:error:2` → startup-line failure surfaced | P1 | |

### grbl_stream_session.txt
| # | Assertion | Level | Notes |
|---|---|---|---|
| T1 | Send-response: each `ok`/`error:` consumed as one ack; push messages never counted | P0 | 2-ack bug class again |
| T2 | `$C` check mode: `[MSG:Enabled]`; no motion; toggle-off auto-resets (welcome again) | P0 | pre-flight validation path |
| T3 | `!` feed-hold → `<Hold:1>` then `<Hold:0>`; `~` resume → `ok` + `<Run…>` | P0 | |
| T4 | `0x18` ctrl-x soft reset mid-run → ALARM:3 (already B9) | P0 | |
| T5 | `$J=…` jog: `ok` per jog; `$J=X99999` → `error:15` (no alarm); jog-cancel 0x85 | P0 | jog ≠ g-code state |
| T6 | `G4 P0.01` sync-dwell pattern accepted; no ack mismatch | P1 | |
| T7 | M2 → `[MSG:Pgm End]` + `ok`; program end surfaced | P1 | |

### fluidnc_boot_status.txt
| # | Assertion | Level | Notes |
|---|---|---|---|
| F1 | Welcome `Grbl 3.9 [FluidNC v3.9.8 (wifi) '$' for help]` → dialect=fluidnc detected | P0 | dialect sniffing for profile |
| F2 | 6-axis `MPos:0,0,0,0,0,0` → parser accepts 3–6 values, pads to 3 | P0 | axis-agnostic |
| F3 | `$H=XY` homes subset — parsed as homing cmd (not g-code) | P1 | |
| F4 | `$ME`/`$MD` motor enable/disable → `ok` | P1 | |
| F5 | `$SD/Run=job.nc` file-run initiated | P1 | FluidNC standalone jobs |
| F6 | `$$` on FluidNC returns subset (`$10=255`) — settings map must tolerate missing keys | P1 | |

## 3. Cross-cutting assertions (all fixtures)

| # | Assertion | Level |
|---|---|---|
| X1 | Chevron `<…>` lines → status report; bracket `[…]` → feedback; `ALARM:` → alarm; `$x=val` → settings; `>` → startup — never `ok`/`error` | P0 |
| X2 | Real-time chars (`?` `!` `~` 0x18) never echoed as acks | P0 |
| X3 | `ok` on empty line is a valid ack (GRBL spec) | P1 |
| X4 | CRLF vs LF tolerance; FluidNC double-`ok` on CR+LF | P1 `[!]` |
| X5 | State transitions legal (Idle→Run→Hold→Idle; Alarm lock) enforced by streamer state machine | P0 |

## 4. Live-hardware backlog `[!]`

These assertions are spec-derived and should be re-validated against a real controller when hardware lands (AGENTS.md: hardware is `[!]` human action):
- S10 inches-report on a real board
- D6 EEPROM write timing (settings writes pause serial RX on AVR)
- X4 CRLF/LF behavior on FluidNC serial
- Any vendor-customized welcome strings / blocked `$I=` (OEMs may lock)
- Real-world alarm pushes ordering (ALARM vs MSG vs reset)

## 5. Build-wave execution order

1. Port fixtures into `ShopPilotTests/Fixtures/grbl/` (checked in) — or wire the checklist as the spec if fixtures must stay in research/raw.
2. Implement parser against P0 set: X1–X3, B1–B9, S1–S3/S6, E1–E3, T1–T5, F1–F2.
3. Harden with P1 set; leave `[!]` items as XCTSkip-annotated tests with a `liveHardware` tag.
4. Every fixture line must be consumed or explicitly ignored — add a "unparsed line" counter assertion to catch new grammar.

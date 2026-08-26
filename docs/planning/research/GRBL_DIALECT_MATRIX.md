# GRBL / FluidNC Dialect Matrix (research evidence)

**Date:** 2026-08-04 · **Sources:** gnea/grbl wiki (v1.1 Commands, Configuration, Interface — fetched), wiki.fluidnc.com (commands/settings, FAQ, serial protocol — fetched), FluidNC README.
**Purpose:** Ground truth for ShopPilot's `ShopPilotSerial` StatusParser + GCodeStream + machine profiles. Golden RX/TX fixtures: `research/raw/grbl_golden/` (gitignored).

---

## 1. Serial transport facts (both dialects)

| Fact | Value | Notes |
|---|---|---|
| Baud | **115200**, 8-N-1 | GRBL default; FluidNC same |
| Line terminator | CR (`\r`) | GRBL: "followed by a carriage return"; FluidNC accepts CR **or** LF, sending both yields 2× `ok` |
| Response | `ok` / `error:N` per line | Streaming protocol is send→wait-for-response (simple) or character-counting; **no XON/XOFF** (removed — broken on ATmega 8U2/16U2) |
| Real-time chars | `?` `!` `~` `^X` (0x18) + extended ASCII 0x80–0xFF | Never enter RX buffer; can be sent mid-stream at any time |
| Push messages | `[MSG:…]`, `[GC:…]`, `[HLP:…]`, `ALARM:N`, `<…>` status, `$x=val`, `>startup:ok`, `[VER:…]`, `[OPT:…]` | Bracketed/chevroned — never counted by streaming protocol |
| Status query rate | ≤5 Hz recommended | 10 Hz possible; CPU tax beyond that |
| Sync trick | `G4 P0.01` dwell | Guarantees planner buffer empty before tool change / next task |

## 2. Status report grammar (GRBL 1.1)

```
<State[:substate]|PosField:x,y[,z…]|optional fields…>
```

- **Always first two fields:** `Machine State` and one position vector (`MPos:` or `WPos:` — v1.1 sends only one; GUI derives the other via `WCO:`: `WPos = MPos − WCO`).
- **States:** `Idle, Run, Hold, Jog, Alarm, Door, Check, Home, Sleep`.
- **Sub-states:** `Hold:0` (complete, ready to resume), `Hold:1` (in progress, reset→alarm); `Door:0/1/2/3` (closed-ready / stopped-ajar / opened-retract-in-progress / closed-resuming).
- **Optional fields** (masked by `$10` status report mask, order not guaranteed):
  - `Bf:15,128` — planner blocks available, serial RX bytes available (**available**, not in-use, since v1.1)
  - `Ln:12345` — line being executed (compile-time option)
  - `F:500` (no variable spindle) or `FS:500,8000` — feed mm/min, spindle RPM
  - `WCO:0.000,1.551,5.664` — work coordinate offset (sum of WCS + G92 + G43.1); appears every 10/30 reports or on change
  - `Pn:XYZPDHRS` — triggered input pins (X/Y/Z limits, P probe, D door, H hold, R reset, S start)
  - `Ov:100,100,100` — feed, rapid, spindle override %; intermittent
  - `A:SFM` — accessory state (S spindle CW, C spindle CCW, F flood, M mist); appears only with Ov field
- `$13` (report inches) changes units of MPos/WPos/WCO/F/FS values.
- **FluidNC:** same grammar; reports can carry up to **6 axes** (`MPos:0,0,0,0,0,0` observed on 3.9.x); `Bf:` and `FS:` present; `Pn:` used. Keep parser axis-agnostic (accept 3–6 values).

## 3. GRBL `$` system commands

| Cmd | Meaning | Notes |
|---|---|---|
| `$$` | View all settings | Ends with `ok` |
| `$x=val` | Write setting | EEPROM; some need soft-reset ($100-102) |
| `$#` | View params: G54–G59, G28, G30, G92, TLO, PRB | `PRB:…:0/1` = probe success flag; `G92`/`TLO`/`PRB` non-persistent |
| `$G` | Parser modal state | `[GC:G0 G54 G17 G21 G90 G94 M0 M5 M9 T0 S0.0 F500.0]` |
| `$I` / `$I=string` | Build info / set custom string | OEMs may lock; `[VER:]` + `[OPT:]` |
| `$N` / `$Nx=line` | Startup blocks (0–1) | Run on reset unless ALARM; `>line:ok` |
| `$C` | Check g-code mode | Parses, no motion; toggle off = auto soft-reset |
| `$X` | Kill alarm lock | Emergency only; `[MSG:Caution: Unlocked]`; startup lines skipped |
| `$H` | Run homing cycle | Only way to home; FluidNC: `$H=XY` homes subset |
| `$J=line` | Jog motion | `$J=X10.0 Y-1.5 F100`; G20/G21/G90/G91/G53 override per-call; independent of parser state; jog-cancel 0x85; soft-limit violation → `error:` not alarm |
| `$SLP` | Sleep mode | Depowers steppers/spindle; exit = reset → ALARM |
| `$RST=$` / `$RST=#` / `$RST=*` | Restore settings / params / all EEPROM | Auto-resets after |
| `$G`-family above | | |

## 4. GRBL real-time commands (for UI: Hold/Resume/Reset/overrides)

| Char | Hex | Action |
|---|---|---|
| `^X` (ctrl-x) | 0x18 | Soft reset (alarm if mid-motion) |
| `?` | 0x3F | Status report query |
| `~` | 0x7E | Cycle start / resume (also from Door/park, M0) |
| `!` | 0x21 | Feed hold (motion decel-stop; spindle stays on) |
| `0x84` | 0x84 | Safety door |
| `0x85` | 0x85 | Jog cancel |
| 0x90–0x94 | — | Feed override 100%/±10%/±1% |
| 0x95–0x97 | — | Rapid override 100/50/25% |
| 0x99–0x9D | — | Spindle override 100%/±10%/±1% |
| 0x9E | — | Toggle spindle stop (HOLD only) |
| 0xA0 / 0xA1 | — | Toggle flood / mist coolant |

Override chars are **extended ASCII** — GUI must send raw 8-bit bytes (e.g. pyserial `b'\x18'`). Feed/rapid/spindle override ranges 10–200%, increments configurable in config.h. **Do not hardcode** — read `Ov:` and render generic buttons.

## 5. GRBL settings table (for the machine-profile editor)

| $ | Meaning | Default | ShopPilot relevance |
|---|---|---|---|
| 0 | Step pulse µs | 10 | expose as advanced |
| 1 | Step idle delay ms | 25 | advanced |
| 2 | Step port invert mask | 0 | advanced |
| 3 | Direction port invert mask | 0 | advanced |
| 4 | Step enable invert | 0 | advanced |
| 5 | Limit pins invert | 0 | advanced |
| 6 | Probe pin invert | 0 | advanced |
| 10 | Status report mask | 1 (v1.1 default 255 in some builds) | **read**: parse fields |
| 11 | Junction deviation mm | 0.010 | advanced |
| 12 | Arc tolerance mm | 0.002 | advanced |
| 13 | Report inches | 0 | **read**: unit handling |
| 20 | Soft limits enable | 0 | **read/write**: preflight |
| 21 | Hard limits enable | 0 | read/write |
| 22 | Homing cycle enable | 1 | **read**: alarm-state behavior |
| 23 | Homing dir invert mask | 0 | advanced |
| 24 | Homing feed mm/min | 25 | advanced |
| 25 | Homing seek mm/min | 500 | advanced |
| 26 | Homing debounce ms | 250 | advanced |
| 27 | Homing pull-off mm | 1.0 | advanced |
| 30 | Max spindle RPM | 1000 | **read/write**: spindle |
| 31 | Min spindle RPM | 0 | read/write |
| 32 | Laser mode | 0 | ignore (laser out of scope) |
| 100–102 | X/Y/Z steps/mm | 250 | **read**: machine geometry |
| 110–112 | X/Y/Z max rate mm/min | 500 | **read**: feed cap |
| 120–122 | X/Y/Z accel mm/s² | 10 | read |
| 130–132 | X/Y/Z max travel mm | 200 | **read**: soft-limit aware jog bounds |

**v0.9 → v1.1 delta:** only `$10` status mask semantics changed + `$30/$31/$32` added. Everything else identical.

## 6. GRBL error codes (parser) — 38 total

`error:N`, N = 1 no letter, 2 bad number, 3 bad `$` cmd, 4 negative where positive expected, 5 homing disabled, 6 step pulse < 3µs, 7 EEPROM read fail, 8 `$` cmd not in IDLE, 9 locked out during alarm/jog, 10 soft limits without homing, 11 line too long, 12 step rate exceeded, 13 door opened, 14 Mega EEPROM line limit, 15 jog exceeds travel, 16 jog malformed, 17 laser mode needs PWM, 20 unsupported G-code, 21 two cmds same modal group, 22 feed undefined, 23 integer required, 24 two axis-using cmds in block, 25 word repeated, 26 axis words missing, 27 N out of range 1–9,999,999, 28 missing P/L, 29 G59.1-3 unsupported, 30 G53 needs G0/G1, 31 unused axis words with G80, 32 G2/G3 no axis words in plane, 33 invalid target (arc/probe at current pos), 34 radius arc math error, 35 IJK arc missing offset, 36 leftover words, 37 G43.1 wrong axis, 38 tool number too high.

**Design note:** on `error:`, controller halts; the **GUI should stop streaming immediately**. Character-counting protocol can't prevent buffered lines — pre-validate with `$C` check mode.

## 7. GRBL alarm codes

| Code | Meaning | UX guidance |
|---|---|---|
| 1 | Hard limit triggered — position lost, re-home | Show "RE-HOME" prominently |
| 2 | Motion target exceeds machine travel — position retained, unlockable | Warn + offer $X |
| 3 | Reset while in motion — position unknown | Re-home recommended |
| 4 | Probe fail (wrong initial state) | Probe setup error |
| 5 | Probe fail (no contact in travel) | Probe depth/feed error |
| 6 | Homing fail: reset during homing | Retry home |
| 7 | Homing fail: door opened during homing | Check door |
| 8 | Homing fail: can't clear limit on pull-off | Increase pull-off / wiring |
| 9 | Homing fail: no limit switch within 1.5× max travel | Check switches |
| 10 | Homing fail: dual-axis second switch not found | Self-squaring issue |

Alarm state: g-code locked out; only `$H` / `$X` / reset accepted; `[MSG:'$H'|'$X' to unlock]` at boot when homing-enabled. Startup lines **do not run** after alarm/$X — always reset after clearing.

## 8. FluidNC vs GRBL (what changes for ShopPilot)

| Aspect | GRBL 1.1 (AVR) | FluidNC (ESP32) |
|---|---|---|
| Config | `$` settings in EEPROM | **config.yaml on flash**; `$GrblSettings/List` shows compatibility settings |
| Machine setup settings | $0–$132 | In config file (axes:, motors:, spindle:); **not** settable via `$` |
| Settings actually supported as `$` | all | `$10` mask + a few runtime (fake responses for $30/31/32); `$Settings/List` (`$S`), `$Settings/ListChanged` (`$SC`), `$Settings/Erase` (`$NVX`), `$Settings/Restore` (`$RST`) |
| Homing | `$H` | `$H`, plus `$H=XY` (home subset); config `homing:` |
| Jog | `$J=…` | `$Jog` / `$J` (same grammar) |
| Motor control | — | `$Motor/Enable` `$ME`, `$Motor/Disable` `$MD` |
| Spindle | `$30/$31` + M3/M4/M5/S | config `spindle:` (PWM, Huanyang VFD, etc.) + speed maps |
| Files | none (host streams) | **SD / LocalFS** — `$LocalFS/*`, `$SD/*`, `$Files/ListGcode`, `$SD/Run` — machine can run jobs standalone |
| Network | none | WiFi AP/STA, telnet, **WebUI** (Esp32_WebUI), HTTP `$ESPxxx` commands |
| Macros | startup blocks $N | `$Macros/Run` (`$RM`) |
| Status | `<…>` same | same format; up to 6 axis values; `Bf:` present |
| Startup msgs | `Grbl 1.1x ['$' for help]` | `Grbl 3.x [FluidNC vX.Y.Z (wifi) '$' for help]` |
| Limits/soft | $20/21 + $130–132 | per-axis in config; same alarm semantics |
| Probing | G38.x + `$6` | G38.x + config `probe:` |
| ATC / tools | T0–T255, no M6 | Tool-changer support in config (`tool:`), still file-based tool change typical |

**Parser compatibility:** "100% compatible with the day-to-day operations of running gcode with a sender" — same send/response protocol, same real-time chars (with the caveat that `?`/`!`/`~` are intercepted even in password fields over serial/telnet — escape with `%xx` UTF-8 sequences).

## 9. ATC vs tool-change-as-files (decision evidence)

- **GRBL:** no M6/T-based auto tool change. T word parses (T0–T255, error 38 beyond). Tool change = separate file per tool, operator swaps bit manually. Same for FluidNC unless the machine has a tool-changer config (rare on hobby class).
- **the incumbent transcripts** (Txafg3oN8c0) confirm the same model on the CAM side: *"visible toolpaths use different tools and the selected post processor does not support tool changing"* → either ATC-capable post or **save to multiple files**. The multi-file save respects toolpath order = cut order, and group-where-possible packs by tool.
- **ShopPilot implication:** post must support (a) per-tool multi-file output with ordered naming, (b) `M6`-less manual tool-change prompts between files, (c) optional T-word emission per tool for ATC-capable FluidNC setups. GRBL `G4 P0.01` sync after pause for manual change.

## 10. Golden fixtures

Written from the spec above (not captured from live hardware): `research/raw/grbl_golden/`
- `grbl_boot.txt` — welcome + alarm-boot + unlock sequence
- `grbl_status_types.txt` — Idle/Run/Hold/Door/Alarm/Home/Jog reports incl. sub-states, Bf/Ln/FS/WCO/Pn/Ov/A fields
- `grbl_settings_$$.txt` — full `$$` dump + `$N` + `$#` + `$G` + `$I` responses
- `grbl_errors_alarms.txt` — error code sampler + ALARM pushes + MSG lines
- `grbl_stream_session.txt` — realistic G-code stream with ok/error, jog, $C check, feed-hold/resume
- `fluidnc_boot_status.txt` — FluidNC boot + 6-axis status + `$H=XY` + `$ME/$MD` + WebUI hints

Fixtures are marked **spec-derived**; when a real controller is available (hardware `[!]` card), capture true RX and diff. Parser/streamer unit tests should be written against the spec-derived set first (they encode the grammar), then swapped to live captures.

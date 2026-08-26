# Post Grammar for GRBL-Class Controllers (Shapeoko / Onefinity / OpenBuilds / FluidNC)

**Date:** 2026-08-04 · **Sources:** gnea/grbl v1.1 docs (fetched), FluidNC wiki (fetched), Carbide3D community (arcs/spindle dwell posts), Shapeoko enthusiast guide, OpenBuilds-CONTROL repo issue (FluidNC compat).
**Purpose:** the grammar ShopPilot's posts must emit for the 90% hobby-router case. This is the *dialect layer*; protocol details (status, alarms, `$` cmds) live in `GRBL_DIALECT_MATRIX.md`.
**Status legend:** `[verified]` = confirmed in official docs/community; `[inferred]` = derived from post-processor conventions.

---

## 1. The GRBL-class feature set a post may assume

| Feature | GRBL 1.1 | FluidNC | Post implication |
|---|---|---|---|
| Absolute/relative | G90/G91 | same | emit G90 header |
| Units | G20/G21 | same | emit G21 (mm) or G20 (in) header — must match machine + CAM units |
| Arcs | G2/G3 with IJK or R | same | **supported** `[verified]`; R-form is fine for GRBL; arcs disabled on some tiny machines — make arc emission a post option |
| Plane | G17 (XY) | same | header G17 |
| Spindle | M3/M4/M5 + S | same (PWM/VFD via config) | M3 S####; **dwell after M3/M5 is the community pattern** (Carbide Motion adds ~2 s) `[verified]` |
| Coolant | M7/M8/M9 | same | emit M9 at end; M8 optional |
| Tool | T0–T255, **no M6** | T + optional tool-changer | never emit M6 unless ATC post; T-word only for ATC setups |
| Cutter comp | G40 (no G41/G42) | G40 | emit G40 header; never G41/42 |
| Work offsets | G54–G59, G10 L2/L20 | same | G54 header; G10 L20 for fixture offset (probe/touch-off) |
| Probe | G38.2–G38.5 | same | separate probe cycle files, not in cut files |
| Dwell | G4 P<sec> | same | use for spindle spin-up/down and tool-change sync |
| Program end | M2/M30 | same | M2 + optional G0 park; M30 resets to top — prefer M2 for sender-based repeat |
| Soft/hard limits | $20/$21 | config | post doesn't emit; machine profile handles |
| Homing | $H (not g-code) | $H / $H=XY | **never emit $H inside a job file** — it's a system command, not g-code |

## 2. Canonical file skeleton (GRBL-class, mm)

```gcode
; ShopPilot post — GRBL-class (gnea/grbl 1.1, FluidNC)
; job: <name> | tool: 1/4" end mill | feed: 1500 mm/min | spindle: 18000 rpm
G17 G21 G90 G94 G40        ; plane XY, mm, absolute, feed/min, no comp
G54                        ; default work coordinate system
G0 Z5.0                    ; safe Z above material (rapid clearance)
M3 S18000                  ; spindle on
G4 P2.0                    ; dwell 2s — let spindle spin up  [verified pattern]
; --- cut ---
G0 X0 Y0
G1 Z-2.0 F300              ; plunge at feed (or ramp)
G1 X50.0 Y0 F1500
...cut moves...
G0 Z5.0                    ; retract
M5                         ; spindle off
G4 P1.0                    ; dwell — let spindle stop (optional)
G0 X0 Y0                   ; park to datum (optional; some shops park at G28)
M2                         ; end, no reset-to-top
```

Inches variant: `G20` instead of `G21`; feeds in in/min; spindle still RPM.

## 3. Machine-family quirks

### Shapeoko (Carbide3D) — GRBL 1.1 class `[verified via community]`
- Runs stock GRBL 1.1 on their boards; Carbide Motion is the stock sender.
- **Arcs work** (G2/G3) `[verified]` — a common complaint is third-party posts that emit arcs which a *custom* firmware build rejects; keep arc output optional.
- Spindle (router) is ON/OFF via M3/M5; Carbide Motion adds a **~2 s dwell** on M3 and M5 for the router to spin up/down `[verified — glue-dispenser post describes the dwell]`.
- Post convention: G90 absolute, G17, G21/G20; no G28 return-to-home in the default Carbide posts (G28 posts from Fusion caused "unexpected homing" reports `[verified]` — avoid G28 in the default post).
- Tool change = separate file per tool (Carbide community advice) — matches the incumbent multi-file save.

### Onefinity — GRBL/grblHAL class `[inferred, community-consistent]`
- Onefinity controllers run GRBL-derived firmware (grblHAL lineage); standard GRBL posts work.
- Community guidance for beginners: depth of cut ~50% bit diameter, router 1–2 on dial, 40–60 ipm feeds `[verified — Onefinity forum]`.
- No ATC on the standard line → file-per-tool workflow again.
- Post implication: stock GRBL post works; keep arcs on (grblHAL handles them).

### OpenBuilds CONTROL / BlackBox — GRBL class `[verified — repo issue]`
- OpenBuilds CONTROL is a GRBL sender; BlackBox runs GRBL-derived firmware. The repo explicitly added **FluidNC compatibility detection** (`indexOf("FluidNC")`) `[verified]` — i.e. one sender serving both dialects, same as ShopPilot's goal.
- Standard GRBL posts apply; spindle via M3/M5 (relay or PWM).
- Their community also uses the same file-per-tool workflow.

### FluidNC — GRBL-compatible + extras `[verified]`
- 100% day-to-day send/response compatibility; same status grammar (up to 6 axes).
- **Job files can live on SD** (`$SD/Run`) — a post could emit a file that runs standalone; sender no longer mandatory.
- Tool-changer config exists in `tool:` YAML — ATC posts possible, but rare on hobby gear.
- Startup macros via `$Macros/Run`; spindle via config `spindle:` (PWM/Huanyang VFD etc.) — S-word semantics identical to GRBL from the post's perspective.
- Parking: `$SLP` + parking motion if enabled — the post can end with a park-to-safe-Z + optional `$SLP` (but `$SLP` disables steppers — only for unattended end-of-day, with a safe park first; GRBL wiki warns strongly).

## 4. Post options ShopPilot's GRBL-class post needs

| Option | Default | Why |
|---|---|---|
| Units (G20/G21) | match job units | mismatched units = 25.4× disaster (see import torture set) |
| Emit arcs (G2/G3) vs line-only | arcs on | some firmwares/builds reject arcs; line-only fallback |
| Spindle dwell (G4 P2) after M3/M5 | on | spin-up/stop safety (community pattern) |
| End behavior: M2 vs M30 vs park | M2 + park to safe Z | M30 rewinds on some senders — dangerous for re-runs |
| G28 park vs datum park | datum (G0 X0 Y0, safe Z) | G28 unexpected-homing complaints |
| Tool change model: file-per-tool vs T-word+ATC | file-per-tool | GRBL has no M6; ATC only for FluidNC tool-changer configs |
| Ramp vs straight plunge | per-toolpath (FM-14) | tool-stress warning in FAILURE_MODE_LAB |
| Header comments | on | operator reads tool/feed/spindle at the machine (the incumbent: notes field, setup sheet) |

## 5. What a post must NEVER emit (GRBL-class)

- `M6` (tool change) unless the machine is a configured ATC (FluidNC tool-changer) — GRBL errors on unsupported g-code (`error:20`).
- `G41/G42` cutter compensation — GRBL only supports G40.
- `G59.1–G59.3` — unsupported (`error:29`).
- `$`-commands or `G28.1/G30.1` inside a job — system commands / EEPROM writes; startup-line and EEPROM writes should never be in a cut file (GRBL wiki warning).
- Line numbers (`N`) unless the sender needs them (optional; keep off by default).
- Non-ASCII comments — GRBL line protocol is US-ASCII only (FluidNC FAQ) — strip smart quotes/accents from comments.

## 6. Verification path

- Golden G-code fixtures per family (Shapeoko/Onefinity/OpenBuilds/FluidNC) — same grammar, different headers; generate when posts land.
- Validate output with GRBL `$C` check-mode (parse-only) before streaming — the exact flow GRBL docs recommend, and the one that catches `error:` blocks pre-cut.
- Cross-check feeds against machine max rates (`$110–$112`) at post time (FM-15).

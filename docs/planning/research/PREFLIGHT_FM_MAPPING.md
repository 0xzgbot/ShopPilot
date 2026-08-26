# Failure Modes → PreflightRule Mapping Spec

**Date:** 2026-08-05 · **Inputs:** `FAILURE_MODE_LAB.md` (FM-01…FM-20), `docs/planning/PREFLIGHT_RULES.md` (R001–R012). **Purpose:** give build waves an implementable table: which failure mode maps to which preflight rule, what's missing, severity, trigger, user-facing copy (from tutors), and which layer detects it. Proposals only — PREFLIGHT_RULES.md body untouched except a cross-link (see §5).

## 1. Rule inventory (existing, from PREFLIGHT_RULES.md)

| Rule | Subject | Severity |
|---|---|---|
| R001 | Open vector gaps | Error (blocks export) |
| R002 | Self-intersecting contours | Error |
| R003 | Zero-length segments | Warning (override) |
| R004 | Duplicate / overlapping vectors | Warning (override) |
| R005 | Toolpath outside stock bounds | Error |
| R006 | Zero tool diameter | Error |
| R007 | No tool selected for strategy | Error |
| R008 | Feed rate exceeds machine limit | Warning (override) |
| R009 | Depth exceeds stock thickness | Error |
| R010 | Tab spacing too tight | Warning (override) |
| R011 | ATC tool-number uniqueness | Error |
| R012 | ATC postprocessor not configured | Error |

## 2. Mapping table

Legend — **detection layer:** `engine` = toolpath/geometry engine at calculate time; `preview` = 3D preview pass; `machine-preflight` = checklist at job start / before streaming (needs no engine change). **Priority:** P0 rows are the lean cut-quality/safety spine; P1 otherwise. `NEW` rules are stubs — create them in PREFLIGHT_RULES.md during the build wave that implements them.

| FM-ID | Failure (from FAILURE_MODE_LAB) | Rule mapping | Severity | Detection layer | User message copy (from tutors) | Priority |
|---|---|---|---|---|---|---|
| FM-01 | Open vector in V-Carve | **R001** (existing) | Error | engine | "V-carving can only be done with closed vectors." → "This shape has a gap — the toolpath can't follow an open line." | P0 |
| FM-02 | Duplicate / overlapping contours | **R004** (existing) | Warning | engine | "This shape is duplicated — you'll cut it twice." | P1 |
| FM-03 | Self-intersecting contour | **R002** (existing) | Error | engine | "This shape crosses itself — the toolpath would cut in two places at once." | P1 |
| FM-04 | Zero-length span | **R003** (existing) | Warning | engine | "This is a zero-length line — it won't cut anything." (auto-fix) | P1 |
| FM-05 | Toolpath outside stock bounds | **R005** (existing) | Error | engine | "This cut goes off your material — you'd cut into empty space." | P1 |
| FM-06 | V-Carve punch-through (wide gaps, no flat depth) | **NEW R013** (stub) | Error | engine | "The distance between these two vectors will allow for your tool to go right through your material… you can control that with your flat depth." → "This carve can go through your material — set a flat depth." | **P0** |
| FM-07 | Part fly-out on last pass (no tabs/vacuum) | **NEW R014** (stub) | Warning | engine + preview | "This square is more than likely going to fly out of place on the last pass." → "This part will be cut free with nothing holding it — add tabs or use hold-down." | **P0** |
| FM-08 | Climb dig-in (backlash) | **NEW R015** (stub) | Warning | engine (machine-profile aware) | "Run test cuts… if the finish looks better on the waste material, switch direction." → "Climb milling on a machine with backlash can dig in — verify direction with a test cut." | P1 |
| FM-09 | Wrong Z-zero / wrong datum | **NEW R016** (stub) | Error (blocks start) | machine-preflight | "This is where we're going to set our tool… off the top of our material… just like I had told the software." → "Confirm Z0 = material surface and XY datum before starting." | **P0** |
| FM-10 | Wrong material thickness | **NEW R017** (stub) | Warning | machine-preflight + engine | "It's actually a little bit thinner than a half inch… always handy to have digital calipers around." → "Measured thickness differs from job setup — verify before cutting." | **P0** |
| FM-11 | Stale toolpath after vector edit | **NEW R018** (stub) | Error (blocks save) | engine | "You will need to recalculate the toolpath" → "This toolpath is out of date — recalculate before saving." | P1 |
| FM-12 | Tool-change collision in single-file save | **R012** (existing, ATC) + **NEW R019** (stub, non-ATC split) | Error | engine (save-time) | "Visible toolpaths use different tools and the selected post processor does not support tool changing." → "Split to multiple files (ordered) or use an ATC post." | **P0** |
| FM-13 | Cutout destroys chamfer (allowance offset) | **NEW R020** (stub) | Warning | engine | "If we do that we're going to end up cutting off our chamfer… remember that 0.15." → "This cutout will remove the chamfer — offset it by the chamfer width." | P1 |
| FM-14 | Ramp/plunge misuse | **NEW R021** (stub) | Warning | engine | "Rather than plunge the tool directly down the z-axis… quite strenuous on the tool." → "Consider a ramp plunge move to reduce tool stress." | P1 |
| FM-15 | Over-aggressive feeds/speeds (chip load) | **R008** (existing, machine limit) + **NEW R022** (stub, chip-load range) | Warning | engine | "Chip load too small → rubbing/heat; too large → chatter/snapped bit" → "Chip load X outside recommended range for material — adjust feed or RPM." | P1 |
| FM-16 | Soft-limit violation | **NEW R023** (stub) | Error (blocks stream) | machine-preflight | GRBL: jog → `error:15`; g-code → ALARM:2 (unlockable) / ALARM:1 (re-home) | P1 |
| FM-17 | Reset-while-motion (position lost) | **NEW R024** (stub) | Error (blocks start) | machine-preflight | "ALARM:3 — Grbl cannot guarantee position. Re-homing is highly recommended." | P1 |
| FM-18 | Feed-rate starvation (start-stop motion) | **NEW R025** (stub) | Warning | machine-preflight | "If the stream can't keep up… start-stop motion" → use character-counting streaming; show `Bf:` when debugging | P1 |
| FM-19 | Probe failure (touch-off) | **NEW R026** (stub) | Error | machine-preflight | "ALARM:4/5 — probe didn't touch; check wiring/depth" | P1 |
| FM-20 | Door/park interplay | **NEW R027** (stub) | Warning | machine-preflight | Show Door sub-state (0–3); never auto-resume on port reconnect | P1 |

## 3. New rule stubs (spec for build wave)

Each stub follows the PREFLIGHT_RULES.md row template (Severity / Trigger / the incumbent suite Equivalent / Plain English / Fix CTA / Verification). Key fields for the P0 stubs:

### R013 — V-Carve Emergent Depth Exceeds Material (FM-06)
- **Severity:** Error (blocks export) — but allow override with explicit flat-depth set.
- **Trigger:** `maxVDepth = f(toolAngle, maxVectorGapWidth)`; if `maxVDepth > (materialThickness − startDepth)` and `flatDepth == unset`.
- **Fix CTA:** "Set Flat Depth" (pre-fill `materialThickness − startDepth − safetyMargin`), or "Warn Only" for engraving-style cuts.

### R014 — Through-Cut Without Hold-Down (FM-07)
- **Severity:** Warning (override).
- **Trigger:** profile toolpath with `cutDepth ≥ materialThickness` AND `tabs.count == 0` AND machine profile has `vacuumHoldDown == false`.
- **Fix CTA:** "Add Tabs" (auto-place, default 4, avoid corners/curves) or "I have hold-down" dismiss.

### R016 — Z0/Datum Contract Acknowledgment (FM-09)
- **Severity:** Error (blocks Start on machine panel, not export).
- **Trigger:** job loaded, machine connected, job not started; requires explicit acknowledgment each job.
- **Fix CTA:** checklist dialog mirroring the job's material setup (datum, Z0 mode, rapid gaps, home) with "Confirm setup" button.

### R017 — Thickness Drift Warning (FM-10)
- **Severity:** Warning.
- **Trigger:** at save/start, `|measuredThickness − jobThickness| > 0.01″` (0.25 mm) when a measured value exists in the machine profile.
- **Fix CTA:** "Use measured value" (updates job thickness) or "Keep job value".

### R019 — Multi-Tool Single-File Save (FM-12, non-ATC)
- **Severity:** Error (blocks save).
- **Trigger:** saving toolpaths with ≥2 distinct tools to one file AND post has no ATC.
- **Fix CTA:** "Split to Multiple Files" (ordered, per toolpath) or "Select ATC post".

## 4. Layer ownership for build waves

| Layer | Rules it owns | Where it runs |
|---|---|---|
| **engine** | R001–R007, R009–R013, R015, R018–R022 | toolpath calculate/recalculate (geometry kernel + toolpath engine) |
| **preview** | R014 (visual tab/bridge + banner), R020 (visual chamfer conflict) | sheet-aware preview pass (SPK-1103) |
| **machine-preflight** | R016, R017, R023–R027 | machine panel before Start / during stream (AGENTS.md non-negotiables #3, #4) |

Engine rules map to existing preflight infra: R001–R004 → SPK-0211/0212; R005/R009 → export gate SPK-0307. Machine-preflight rules are new surface — a checklist sheet on the machine panel, not the export gate.

## 5. Cross-link (one line, only addition to PREFLIGHT_RULES.md)

Append to PREFLIGHT_RULES.md header block:
> Machine-outcome failure modes FM-01…FM-20 and their rule mapping: `docs/planning/research/PREFLIGHT_FM_MAPPING.md`.

## 6. Open questions for build waves

1. R013 severity: the incumbent suite **clamps** depth rather than erroring (R009 verification note). Recommend: block-with-override, not hard clamp, to match tutor guidance ("you can control that with your flat depth").
2. R014 needs a machine-profile field `vacuumHoldDown` — add to profile schema (parallel to GRBL `$20/$21` fields).
3. R017 "measured thickness" source: add a quick caliper prompt to the job-setup flow, or read from a saved machine profile. Decide at build time.

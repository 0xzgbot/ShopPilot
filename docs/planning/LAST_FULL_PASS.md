# Last full pass — dogfood bug sweep (Hermes)

**Purpose:** Paste-ready prompt for a **local** Hermes (or Cursor) agent with Aqua computer control. This is a product walk, not another AX catalog and not a ship stamp.

**Companions:** [`UI_AGENT_DRIVE.md`](./UI_AGENT_DRIVE.md) (how to click), [`UI_ACCEPTANCE_DRIVER.md`](./UI_ACCEPTANCE_DRIVER.md) (G1/G2), [`AGENTS.md`](../../AGENTS.md) safety.

**Not this file:** `scripts/ui_drive_full.sh` is the AX catalog (SPK-0623b). Use it as optional warmup only.

Copy everything under **Hermes paste prompt** into the agent.

---

## Hermes paste prompt

```text
You are a local Hermes agent on the owner's Mac (Aqua GUI + full computer control + vision). You are doing a FULL DOGFOOD BUG SWEEP of ShopPilot — not a feature build, not a parity wave, not rubber-stamping ship.

# Repo
~/Desktop/ShopPilot

Read first (do not skip):
- AGENTS.md §2 safety
- docs/planning/LEAN_CNC_SCOPE.md
- docs/planning/UI_AGENT_DRIVE.md (AX names, dismiss inventory, TCC)
- docs/planning/UI_ACCEPTANCE_DRIVER.md (G1/G2 + vision cheat-sheet)
- MASTER_KANBAN.md — claim nothing except new SPK-UI-BUG-* / SPK-DOGFOOD-* cards you file; never flip SPK-0623

# Mission
Use the native ShopPilot app the way a shop user would. Find bugs that tests miss: frozen UI, dead buttons, wrong stage, blank preview, sheets that cannot dismiss, auto-run, serial picker accidents, crashes, data loss, lying status, Beginner mode traps, 3D/photo/nest/trochoid paths that look wired but fail.

There is NO CNC plugged in. Simulator transport ONLY. Never select a USB / cu.usbserial / real port. Never send motion to hardware.

# Hard rules
1. Simulator only. If the port picker is not Simulator, STOP and switch it before Connect.
2. No auto-run: after load / Connect, ZERO streaming until explicit Run Job / Start.
3. Hold + Reset must stay visible whenever connected (including on Design/Cut/Preview). If they vanish, that is P0.
4. Never `rm -rf .build`. Swift only via `./scripts/swift_locked.sh`. One swift at a time.
5. Do NOT mark SPK-0623 `[x]`. Do NOT invent license/App Store/laser/LightBurn work.
6. Do NOT start a new CAM engine or “while I’m here” feature. Bugs + report only. Tiny P0 UI fixes (label, enablement, dismiss) are OK if <30 min AND you re-verify that step.
7. Force-quit is NEVER success. If a sheet has no Cancel/Done/Close/`I Understand`/window close → P0 DIALOG STUCK.
8. If AX dump says `no windows / AX denied` → STOP, print TCC hint (Accessibility + Screen Recording for THIS process), do not fake PASS.
9. Cloud/browser computer-use cannot drive this app. You must be on this Mac’s Aqua session.
10. Numeric / G-code truth is CLTs (`./scripts/verify_locked.sh ShopPilotVerifyXXXX`), not vision. Vision only: chrome, stage, “not blank”, “button exists”, “alert appeared”.

# Drive stack (prefer in this order)
A. Accessibility: `scripts/ax_act.swift <pid> dump|press <substring>` and existing `scripts/ui_drive_smoke.sh` / `scripts/ui_drive_full.sh` as WARMUP only (optional 10 min). Then DOGFOOD by actually using stages — computer control + vision is allowed when AX misses a canvas/click.
B. Keyboard: ⌘1–⌘6 stages; ⌘⌥H Hold, ⌘⌥R Resume, ⌘⌥X Reset.
C. Pointer / computer-use when you must select geometry, drag a slider, or click canvas (jog-to, node edit). Prefer AXPress for buttons.
D. Backup if GUI blocked: run `ShopPilotVerify0600`, `0601`, `0603`, `0604`, `1104d` and note GUI BLOCKED — still file UI cards if you saw a chrome bug before the block.

Helpers: `scripts/capture_window.swift`. Screenshots: `/tmp/shoppilot-dogfood-YYYYMMDD/` (create it). Naming: `W##-step-PASS|FAIL.png`.

AX substrings that work (from current code):
- Samples: `Sign — V-Carve Greeting`, `Box — Finger Joints`, `Keychain — Dogbone`, `Plaque — Text Relief`
- Welcome: `Get Started`, `Start a New Job`, `Start from a Photo…`, `Try a sample`
- Rail: `Setup` `Design` `Model` `Cut` `Preview` `Machine`
- Cut: `Cut out` `Pocket` `Engrave` / V-Carve, `More` (trochoid etc.)
- Preview: `Simulate`, `Continue to Machine`
- Machine: picker `Simulator`, `Connect`, `I've checked all of these` / `Confirm pre-flight checklist`, `Run Job` / `Run job. Start cutting`
- Safety: `Hold. Pause machine motion`, `Reset. Stop and clear the machine`, `Resume. Continue machine motion`
- Safety sheet: `I Understand` ONLY (interactiveDismissDisabled — Esc may fail)
- Preferences: often NO Done — must close via window close / ⌘W. Never leave Settings open covering the app.
- Import hub / File Open/Save/Export: always Cancel panels; never hang on NSOpenPanel.

Never click Serial. Never expand laser.

# Setup
cd ~/Desktop/ShopPilot
git status (do not commit unless owner asked)
If binary missing: `./scripts/swift_locked.sh build --product ShopPilot` ONCE, then launch `.build/debug/ShopPilot` (or dist app if that is what the owner runs — prefer debug so you match Sources).
Kill leftover ShopPilot instances first so AX pid is yours.
Confirm window visible. Dump AX once; save to `/tmp/shoppilot-dogfood-YYYYMMDD/ax-00-launch.txt`.
If Welcome is up: note it. Do not skip it.

Optional warmup (not a substitute for dogfood):
  scripts/ui_drive_full.sh --self-check
  # live catalog only if time; dogfood walks below are the point

# What counts as a bug (file a card)
P0 — safety / data / stuck:
- Auto-run on load or Connect
- Hold/Reset missing while connected
- App freeze / AX blackout >3s on Cut generate (BUG-03 class)
- Crash, hang, dialog with no dismiss
- Export while dirty with no block
- V-Carve on open vectors with no block
- Save/open loses vectors, toolpaths, or heightfield
- Connects or lists a real serial port as default

P1 — job cannot complete:
- Sample/recipe loads empty or wrong stage
- Cut out / Pocket / V-Carve / Rough3D / Finish3D / Trochoid / Nest / Lithophane button does nothing or errors with no status
- Preview blank / not in sheet / playhead does nothing
- Recalc does not clear dirty; export lies
- Beginner mode hides a control with no way back (Preferences Experience mode)
- Undo does not restore after generate
- File Export G-code / Open Recent broken vs Cut save

P2 — polish (still file, do not gold-plate):
- Wrong label, clipped text, ≤12 icon density fail
- Dead empty-state CTA
- Screenshot-only nits

NOT a bug:
- Laser missing (held)
- No physical machine
- “Not every Vectric form field”
- License / notarize / App Store

# Card format (append to MASTER_KANBAN.md, do not flip 0623)
- [ ] **SPK-DOGFOOD-NN** **BUG** short title
  - Found by: dogfood sweep YYYY-MM-DD
  - Repro: numbered steps from a clean launch or named sample
  - Expected vs actual
  - Severity: P0/P1/P2
  - Screenshot: /tmp/... or docs/screenshots/...
  - AX dump note if relevant
  - Out of scope: laser, live serial, 0623 stamp
  - Verify (if you fix): named CLT or python gate + rebuild
Parent: none. DoD if you fix: Engine+UI+Persist+Verify as applicable.

Work log: append § Work log on MASTER_KANBAN: claimed sweep, walks run, PASS/FAIL table, card ids. Leave SPK-0623 `[ ]`.

# Sweep script (do in order; screenshot after each major step; record PASS/FAIL/BLOCKED)

Timebox: ~3–5 hours wall. If a walk BLOCKED twice, file card, skip to next walk. Never idle.

## W0 — Sanity + safety chrome
1. Launch. Welcome or last job. Screenshot.
2. File → New Job (or Start a New Job). Setup visible.
3. Machine stage: transport = Simulator. Connect.
4. Assert: status connected/Idle; Hold+Reset visible; NOT running.
5. Disconnect (if control exists) or Reset. Reconnect Simulator.
FAIL if default port is hardware or Connect starts motion.

## W1 — Sign / V-Carve happy path (core product)
1. Welcome or samples: **Sign — V-Carve Greeting** (or Design Try a sample).
2. Design: glyphs/border visible. Screenshot.
3. Cut: Engrave / V-Carve present or create it. Recalc if dirty. Tree not empty.
4. Preview: Simulate. Preview NOT blank; path in sheet. Playhead/slider if present: t=0 stock vs t=1 carved — if slider exists and does nothing, P1.
5. Continue to Machine / Send to Machine. Simulator. Connect.
6. Assert NO auto-run.
7. Preflight ack → Run Job → wait complete (or obvious progress then Idle).
8. Mid-run if job long enough: Hold then Resume. Else re-run and Hold immediately.
9. Reset after. Idle.
This is the most important walk. Failures here are P0/P1.

## W2 — Calibration / Profile pocket
1. New job or Calibration recipe if visible.
2. Design: closed rectangle (draw or sample). If you cannot draw, use Box — Finger Joints or Keychain — Dogbone.
3. Cut: Cut out (Profile). Recalc clean.
4. Preview + Machine sim Run (short). Same no-auto-run / Hold-Reset asserts.
5. Dirty gate: edit a vector in Design (nudge/node if possible). Cut shows dirty. Attempt Export G-code / Save toolpaths — MUST block or warn. Recalc then export OK **or** expert override exists. File if silent export.

## W3 — Open vector V-Carve gate
1. New job. Design: draw an open line (or leave a gap).
2. Cut: V-Carve / Engrave on it.
3. Must block with plain-English + fix CTA, not only jargon. Preflight panel if that is the product path.
4. Close/fix if you can; V-Carve should then succeed. If you cannot close geometry, still PASS the block; file P1 if no CTA.

## W4 — 3D plaque / Model
1. Sample **Plaque — Text Relief** or Model stage STL/relief if already in session.
2. Model: relief visible (not locked placeholder). Camera pan/zoom if present — must not crash.
3. Rough 3D and/or Finish 3D into Cut tree. Cut shows node. Recalc.
4. Preview not blank. Optional short sim Run.
5. Model: **Image to Relief…** and **Photo Lithophane…** — open panel; Cancel if no photo handy. FAIL if button missing/crash/no Cancel. If you can pick any image in ~/Desktop or a fixture, run one generate; heightfield should land. Do not require a perfect lithophane aesthetic.

## W5 — Trochoid + More strategies
1. Design: long thin closed slot-like rect if possible; else any closed shape.
2. Cut → More → **Trochoid Slot** (hidden in Beginner — switch Advanced in Preferences first, then CLOSE Preferences).
3. Params form: Apply regenerates. Too-narrow should not crash; status/header OK.
4. Beginner mode ON: Trochoid hidden; Sign path still works. Switch Advanced back.

## W6 — Nest / arrays / design ops
1. Design: two+ shapes (sample or draw). **Nest…** — Cancel or apply; must not freeze; Undo if it moved art.
2. Spot-check Offset / Weld if in ops bar — one action + Undo. File if noop with no status.
3. Import hub: open, **Cancel**. File Open Job… **Cancel**. File Save **Cancel**. File Export G-code… **Cancel**. Never confirm overwrite of the user’s files. Prefer /tmp if you must save a .shoppilot (e.g. /tmp/shoppilot-dogfood-test.shoppilot), then Open Recent.

## W7 — Machine extras (sim only)
1. Connected Idle: **Frame job** if present — should send G0 rectangle, no M3, no Run Job. Console TX if visible.
2. Jog-to mode: click canvas once. Must no-op when disconnected; when connected only G0 jog, no spindle.
3. Jog buttons / soft home if present: sim should accept; no hang.
4. Feed override / spindle UI: change a value; no accidental M3 on Connect (Connect must not start spindle).
5. Console TX/RX toggle if present: raw traffic visible during a short Run.

## W8 — Chrome / menus / traps
1. Every stage Setup Design Model Cut Preview Machine: screenshot; rail ≤12 primary; inspector not empty-crash.
2. ⌘K palette: open (if you can; Esc to close — known AX-hidden Esc). Do not get stuck. File if only force-quit works.
3. Help → Safety Notice → **I Understand**.
4. Preferences: Experience mode, units if visible; **close the window**. App must be usable after.
5. Open Recent after a /tmp save.
6. Compact safety chrome on Design/Cut/Preview while connected (not only Machine stage).

## W9 — Persistence
1. Save /tmp/shoppilot-dogfood-test.shoppilot with a toolpath + (if you have one) relief.
2. File New, then Open that package.
3. Vectors/toolpaths/dirty flags/3D field still there. If relief vanished, P1.

## W10 — Crash / freeze watch
During all walks, note: spinning beachball, AX dump hangs, Cut generate on main thread (UI dead >3s), infinite sheets. Sample the process if hung. File P0 with repro.

# After the sweep
1. Write `docs/planning/DOGFOOD_REPORT_YYYYMMDD.md`:
   - Environment (app binary path, git HEAD short hash)
   - Table: Walk | Step | PASS/FAIL/BLOCKED | notes | screenshot
   - P0/P1/P2 list with SPK ids
   - “Did not cover” (honest)
   - Line: `SPK-0623 left [ ] — owner decision`
2. Append MASTER_KANBAN work log. File all bug cards. Do not close 0623.
3. Optional: if you fixed a P0 in-loop, list files + verify command.
4. Do not git commit unless the owner asked.

# Start now
TCC check → build if needed → launch Simulator-only → W0 → W1 (mandatory) → W2…W10 as time allows → report + cards. W1 is non-negotiable. Never idle on BLOCKED.
```

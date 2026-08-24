# ShopPilot Dogfood Bug Sweep — 2026-08-22

> **Status update 2026-08-24:** every bug filed by this sweep (**SPK-DOGFOOD-01…05**) has been
> fixed, CLT-verified, and marked `[x]` on MASTER_KANBAN (fixes landed 2026-08-23). The walk
> table below is preserved as-found from the sweep day. SPK-0623 remains `[ ]` — owner decision.

Full dogfood sweep of the native debug build, driven as a shop user would use it.
Simulator transport ONLY. No hardware touched. SPK-0623 left `[ ]` — owner decision.

---

## Environment

- Repo: `~/Desktop/ShopPilot`, branch master, HEAD `0ea330e` (feat(cam): SPK-1910 trochoidal slotting)
- Binary: `.build/debug/ShopPilot` rebuilt fresh via `./scripts/swift_locked.sh build --product ShopPilot` (10.5s, green)
- Host: owner's Mac, Aqua session, Accessibility TCC granted to driving process
- Drive stack: `scripts/ax_act.swift` (window-scoped AXPress + role filters), `scripts/capture_window.swift`,
  ad-hoc `/tmp/shoppilot-dogfood-20260822/ax_hit.swift` (app-scoped hit-test probe) and
  `ax_drag.swift` (CGEvent drag probe)
- Screenshots + AX dumps: `/tmp/shoppilot-dogfood-20260822/`
- Vision model backend was DOWN most of the session (`unsloth/Qwen3.6-35B-A3B-NVFP4` 404) —
  canvas asserts were made from AX dumps + engine source reads instead. Numeric truth came from a
  headless Core repro compiled against `Sources/ShopPilotCore/*.swift` (see DOGFOOD-01).

## Headless ground-truth repro (DOGFOOD-01)

`SampleProjectsStore.makeSignPayload()` builds the Sign sample on a **600×400mm sheet**, but the
default simulator/MachineProfile travel envelope is **500mm** (`MachineProfile` defaults,
`SimulatorTransport.travelLimitMM = 500`). Streaming the generated V-Carve (+clearance) G-code through the real
`SimulatorTransport`:

```
total gcode lines: 3843
FLAG [#9]  G1 X585.000 Y15.000 F1000 -> X585.000      (566 flagged tokens >500 total)
GROUND TRUTH: ALARM at line #9: G1 X585.000 Y15.000 F1000
previous line: G1 Z-1.000 F300
```

Line 1 = safe-Z retract (ok), line 9 = first X585 move → `ALARM:Soft limit`. In-app the stream died the same way
(Raw TX/RX console captured `ok` → `ALARM:Soft limit` → `<Alarm|MPos:0,0,5.000>`).

---

## Walk table

| Walk | Step | Result | Notes | Screenshot |
|---|---|---|---|---|
| W0 | Launch + recovery sheet | PASS | Autosave recovery sheet appears after dirty kill; Discard/Recover both AX-pressable | W00-launch-PASS.png |
| W0 | Setup stage visible | PASS | Empty "Untitled Project", recipe CTA + Material Setup render | W00-launch-PASS.png |
| W0 | Simulator transport select + Connect | PASS | Default radio = Simulator; Connect → `Idle`; console shows GRBL reports | W00-connected-idle-PASS.png |
| W0 | Hold + Reset visible when connected | PASS | Both fixed-chrome buttons exposed on Machine stage | W00-connected-idle-PASS.png |
| W0 | Disconnect → Reconnect cycle | PASS | ×3 across the session, always returns to Idle, no auto-run | — |
| W0 | Safety disclaimer visible | PASS | "Software Hold is a complement to … hardware e-stop." banner | W00-connected-idle-PASS.png |
| W1 | Load Sign — V-Carve Greeting sample | PASS | Design empty-state "Try a sample" loads 20 vectors (BUG-01 fix live-confirmed) | W01-design-sample.png |
| W1 | Sample art renders | PASS* | HELLO glyphs + gear medallion + border seen on canvas (vision-assisted before vision outage) | W01-design-sample.png |
| W1 | Cut: Engrave/V-Carve generate | PASS | Clearance + V-Carve nodes in tree, 2659 lines, 4 passes, dirty=0, NO main-thread freeze (BUG-03 fix live-verified) | — |
| W1 | Preview renders | PASS | Wireframe paths on stock block, job stats line, heightfield sim completes (240k cells) | W01-preview-initial/simdone.png |
| W1 | Continue to Machine → Connect | PASS | "14541 lines ready" / "5156 lines ready", no auto-run | — |
| W1 | Preflight ack → Run Job | **FAIL** | **Instant ALARM:Soft limit at stream line ~9 — job can never complete (DOGFOOD-01)** | W01-run-alarm-FAIL.png |
| W1 | Reset clears alarm → Idle | PASS | Alarm banner clears, Run properly re-disabled until preflight re-confirm (honest enablement) | — |
| W1 | Hold/Resume mid-run | BLOCKED | Impossible while DOGFOOD-01 alarms at line ~9 (covered by Verify0417a CLT) | — |
| W2 | Dirty badge after design edit | PASS | "Edited" badge + stale-toolpaths tip + "Document dirty" chip all appear | W06-preview-stale.png |
| W2 | Save Toolpaths while dirty | PASS | Blocked by preflight alert with plain-English issue + Warn Only/Set Flat Depth/Cancel; Cancel dismisses cleanly | W02-preflight-alert.png |
| W2 | Recalculate Dirty | PASS | Recomputes, alert re-fires only for genuinely out-of-envelope geometry | — |
| W3 | Open-vector V-Carve gate | PASS (CLT) | Pointer-blocked (CGEvent clicks are silent no-ops here) so no open vector could be drawn in-UI; engine gate proven by Verify0211 + Verify0604 re-run PASS 2026-08-22 (plain-English fix CTAs, closed designs carve freely) | W03-vcarve-gate.png |
| W4 | Model stage empty state | PASS | "No 3D relief yet" + helpful CTA text, inspector renders | W04-model-empty-PASS.png |
| W4 | Image to Relief… panel | PASS | Panel opens (AX window "Import Image to Relief"), Cancel dismisses | W04-image-relief-panel.png |
| W4 | Photo Lithophane… panel | PASS | Same — opens + Cancel dismisses | — |
| W4 | Import menu inventory | PASS | SVG/DXF/WebP, STL/OBJ/3MF Relief, EPS/PDF/DWG all present | — |
| W5 | More → Trochoid Slot | **FAIL (perf)** | Generates (11673 loops × 3 passes, 12021 lines) but app AX-blackout ~4 min at 95% CPU (DOGFOOD-03) | — |
| W6 | Import hub sheet Cancel | PASS | Sheet opens, Cancel dismisses, no hang | — |
| W6 | Preview after edit | PARTIAL | Stale-warning appears correctly, but preview re-render froze minutes-long (DOGFOOD-03) | W06-preview-recovered.png |
| W7 | Console Raw TX/RX toggle | **FAIL** | Enabling raw mode during alarm → main-thread re-render storm (DOGFOOD-02) | W01-alarm-rawtxrx.png |
| W7 | Feed override / spindle / Frame / jog | SKIPPED | Timebox consumed by DOGFOOD-02/03 freezes; sim accepts manual console input field (present) | — |
| W8 | Stage rail density ≤12 | PASS | 6 primary stage buttons; each stage toolbar fits one row | all screenshots |
| W8 | Menus present | PASS | Full File/Edit/View/Stage/Window/Help catalog in AX tree | ax-00-launch.txt |
| W8 | Keyboard (⌘K, ⌘W, shortcuts) | BLOCKED | App cannot take focus from background Hermes session (known env limitation) | — |
| W9 | Save/Open .shoppilot package | PARTIAL | Recover-from-autosave path proven (vectors + 2 ops restored, preview re-sims); explicit Save/Open panels are out-of-process (untestable from background session) | W09-recover-PASS.png |
| W10 | Crash/freeze watch | **FAIL** | Two multi-minute main-thread freezes captured with `sample` profiles (DOGFOOD-02, DOGFOOD-03); no hard crash | /tmp/sp-sample*.txt |

## Findings

### P0

**SPK-DOGFOOD-02 — Raw TX/RX console + alarm = main-thread re-render storm (app-wide AX blackout 15+ min)**
With Raw TX/RX enabled, every status poll (`?` @500ms) lands in `consoleLog`, each append fires
`objectWillChange` → `MachineConnectionView.body` rebuilds → the 500-message `ForEach(Array(consoleLog.messages))`
re-diffs → `$currentStatus` sink sets `chromeState` → another invalidation. Post-alarm the loop pins the main
thread at ~95% CPU (sample: 567/1100 samples inside `chromeState.setter → Published.send → AttributeGraph.update`),
the AX server stops answering entirely, and the app never recovers (observed >15 min twice; had to kill).
Without raw mode the same alarm stayed responsive — the console ForEach diff is the trigger.

### P1

**SPK-DOGFOOD-01 — Flagship Sign sample cannot run: sheet 600×400mm vs 500mm sim travel envelope**
The bundled sample's clearance pass cuts at X=585 (>500). Every Run Job ends in `ALARM:Soft limit` within the
first lines. Nothing warns at Setup/Cut/preflight, and the alarm text ("Motion stopped; press Reset to clear")
never mentions travel limits or which axis/coordinate tripped — a beginner reads this as an app/machine fault.
Fix options: size the sample sheets to fit the default envelope (≤500×500), raise the simulator profile travel
to match sample stock, or add a preflight rule comparing job extents vs profile travel with a plain-English CTA.

**SPK-DOGFOOD-03 — Trochoid Slot + big-buffer preview: minutes-long main-thread stalls**
Pressing More → Trochoid Slot on the Sign sample produced a valid 12k-loop result but froze the UI ~4 min at
95% CPU; returning to Preview stalled again for several more minutes. `sample` profiles show the hot path is
`ToolpathPreviewView.cachedWire()` → `WireframeRenderer.detectPeckRetracts` whose confirmation loop calls
`lastXBefore(line, in:)` (a full re-scan of the buffer) once per candidate retract — O(candidates × lines²)
on 14.5k-line buffers — plus full re-segmentation whenever the signature changes, all on the main thread.
Trochoid also applied to *every* closed vector in the session (gear, satellites, letters) rather than a selected
corridor, multiplying the damage. Fix direction: single-pass peck detection (track last-plunge inline),
compute wireframes off-main (pattern already exists in `generateToolpathAsync`), and require a selection.

### P2

**SPK-DOGFOOD-04 — Lying status: "Material sim ready (0 cells)"**
After Recover-from-autosave (and after any buffer invalidation), the Preview status claims the material sim is
ready while carrying zero simulated cells; heightfield mode has nothing to show until Simulate re-runs.
Should read "Material sim empty — press Simulate".

**SPK-DOGFOOD-05 — Driver tooling: `ax_act.swift dump` SIGILL-crashes at depth ≥7 on complex stages**
The interpreter dies (Illegal instruction, JIT force-cast class) walking deep SwiftUI trees (Design/Cut with
populated canvases). All presses stay reliable; only full-depth dumps die. Worked around with depth-limited
dumps + an app-scoped hit-test probe (`ax_hit.swift`). Fix the unsafe casts in `walk`/`collect` or compile the
driver instead of interpreting it.

## Positives confirmed (no card)

- Zero auto-run anywhere: load/connect/stream-ready states never move the machine without explicit Run Job.
- Hold + Reset remain fixed chrome while connected on Machine, and persist in the top chrome on Design/Cut/Preview.
- Honest enablement: Run disabled until preflight confirm; after Reset it re-disables (re-confirm required).
- Preflight doctor copy is excellent plain English with fix CTAs ("Set Flat Depth").
- BUG-01/BUG-02/BUG-03 fixes verified live (Try-a-sample AX-exposed, Advanced disclosure reachable,
  V-Carve generation no longer freezes the app).
- Autosave recovery round-trips vectors + toolpath ops; Preview re-simulates after recovery.
- Image-to-Relief / Photo Lithophane / import hub all open and cancel cleanly; no dialog traps found.

## Did not cover (honest)

- Keyboard-driven surfaces (⌘K palette, ⌘W, stage shortcuts) — app focus refused from background session.
- NSOpenPanel/NSSavePanel interiors (Save/Open Job, Export G-code) — out-of-process panels untestable here;
  cancel discipline verified only for the in-app Import hub sheet.
- Beginner↔Advanced Preferences toggle (same focus limitation); Trochoid hidden-in-Beginner asserted from source.
- Jog/frame/feed-override/spindle UI on the simulator (timebox spent on the two freezes).
- Hold/Resume mid-run in-app (blocked by DOGFOOD-01 alarming at line ~9; CLT-covered by Verify0417a).
- Live serial, laser, license/notarization — out of scope by mission.

## Environment traps encountered (documented, NOT product bugs)

- Unfocused menu-bar AXPress went through LaunchServices and launched the **dist** app alongside the debug
  binary (both later SIGTERMed together). Rule for future walks: never press menu items; window scope only.
- CGEvent clicks/drag posts are silent no-ops in this environment (matches skill notes) — pointer-only
  interactions (drawing, slider drags) cannot be exercised from here.
- System-wide `AXUIElementCopyElementAtPosition` resolves to the frontmost app's scroll-area container and
  fails (-25206) — always hit-test app-scoped.

## Line required by mission

SPK-0623 left `[ ]` — owner decision.

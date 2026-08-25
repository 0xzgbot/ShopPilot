# Family Quality Implementation Plan (rev 2, 2026-08-25)

> **For Hermes:** Execute card-by-card per `AGENTS.md` §0. Each card below is one
> 45–90 min slice: failing CLT → implement → green → build → commit. File new cards
> on `MASTER_KANBAN.md` (Mac) and `HERMES_KANBAN.md` (Win) before claiming. Never
> mark SPK-0623 `[x]`. Never pick SPK-1900g license.

**Goal:** Close the three gaps that actually lose users — cut quality (inlay fit),
machine conversation (LightBurn-class control), first hour (repair + presets +
welcome) — plus the family trust contract, per the 2026-08-24 feature-review canvas.

**Architecture:** Two native apps, one intended `.shoppilot` document. Mac leads;
Windows mirrors semantics card-for-card in the same wave. Shared G1-hash goldens are
the drift contract.

**Tech Stack:** Swift 5.x, CLT verifiers (`Sources/ShopPilotVerify*/main.swift`) —
**gate is `./scripts/verify_locked.sh ShopPilotVerifyXXXX`. CLT has no XCTest; never
default to full-package `swift test`** (full sweep only at wave close). Windows gate
is `./verify.sh [FullyQualifiedName~filter]`, Release, zero warnings.

**Ordering (pain × uniqueness):**
doctor repair → inlay physics → XYZ/TLS probe → device profile + feeds seed →
presets / welcome / CTA (first hour) → T-bones / rest pocket → toggle-ops →
macros/alarms → goldens / air-cut / license.

---

## Ground truth established 2026-08-25 (grep-verified at HEAD)

- **V-carve valley semantics: DONE.** `MedialAxis.swift` + width-Z + flat-area
  clearing shipped (SPK-2010a–e `[x]`; Win `FlatAreaClearing` P-202 `[x]`). **Closed
  — do not reopen medial-axis.** Remaining quality loss = inlay physics + photo bar.
- **Vector doctor: real engine gap, not just wiring.** `JoinCloseTrim.joinLines`
  chains `.line` pairs only at 1e-6 tolerance; `joinPolylines` exists but same hard
  tolerance. Sign letters from text-to-curves are `.freehand` polylines with ~0.1 mm
  gaps → today's join misses them. `suggestedFix` results are copies, not applied.
  No delete-zero-span API. Engine card required before doctor buttons.
- **Inlay:** `InlayToolpath.swift` has pocket/plug clearances + recipes; no tip Ø,
  glue gap, or compression fudge. Real gap.
- **Rest pocket: no 2D engine on either platform.** Win `PreviousToolDiameterMm` is
  HeightfieldToolpath-only; Mac `PocketToolpath.swift` has zero rest hits. An engine
  slice precedes any form field. (UI-without-engine is forbidden by both AGENTS.)
- **Probe planning lives in `MachineController.touchOffZ` → `TouchOff.plan/.gcode`
  (`MachineController.swift:393`).** Extend that planner for XYZ/TLS. The streamer
  stays ok-wait + realtime only.
- **True gaps (zero hits both platforms):** device profiles, XYZ+TLS, skip-first-M6,
  start-from-here/resume, park/bit-change macros, ALARM decode banner, chip-load
  preflight, T-bones, copy-along-path.
- **Chip-load seed data:** `docs/planning/research/BIT_FEEDS_LIBRARY.md` — a doc, not
  Sources. Card 2023a creates JSON from it.
- **First-hour state:** samples exist (`SampleProjectsStore`, welcome overlay CTAs)
  but gallery is not the first screen; no per-stage forward CTA; Mac has no
  material+bit preset fill loop (Win H-501 does).

---

## Phase 1 — Repair (run first: highest leverage, lowest risk if the engine is honest)

### Card SPK-2020a0 · ENGINE — polyline join/close with gap tolerance + zero-span delete

**Objective:** Make repair honest for real sign vectors before any button exists.

**Files (Mac):**
- Modify: `Sources/ShopPilotGeometry/JoinCloseTrim.swift`
- Test: new `Sources/ShopPilotVerify2020a0/main.swift`

**Steps:**
1. Failing CLT: two `.freehand` polylines with 0.1 mm endpoint gap → new
   `joinAll(shapes:, tolerance:)` returns one merged shape; at default
   `tolerance: 0.1` sign-letter gaps close; at `tolerance: 0` behavior matches today.
2. Add `deleteZeroSpan(_ shapes:) -> ([kept], [removed])` (zero-length / degenerate).
3. Add a single session-facing entry point that *applies* results (mutates the shape
   list and returns counts) — do not leave callers applying `suggestedFix` copies.
4. Verify: `./scripts/verify_locked.sh ShopPilotVerify2020a0` PASS + nearest
   geometry regression verify green + app target builds via
   `./scripts/swift_locked.sh build --target ShopPilot`.
5. Commit `feat(SPK-2020a0): polyline join tolerance + zero-span delete`.

### Card SPK-2020a · UI — doctor one-tap repair + V-carve Fix CTA (deps: 2020a0)

**Objective:** Doctor panel Join All / Close All / Delete Zero-Span buttons that mutate
the session (undoable); V-carve refuses open paths with a Fix affordance, not bare ignore.

**Files (Mac):** Modify `Sources/ShopPilot/PreflightDoctorView.swift`,
`AppSession.swift` (undoable repair entry calling the 2020a0 API),
V-carve preflight failure alert.
**AC:** fixture with open polylines + zero-span shapes repairs in one tap, undo
restores, dirty flag set, "N repaired, M remain" shown; V-carve open-path failure now
offers Fix → repairs → revalidates.
**Gate:** `./scripts/verify_locked.sh ShopPilotVerify2020a`.
**Win mirror:** H-601 over the same engine contract once its join tolerance lands.

---

## Phase 2 — Cut quality: inlay physics (+ photographic bar)

### Card SPK-2021a · Inlay wizard physics (both apps, same wave)

**Objective:** One source vector produces paired pocket + plug ops that fit by
construction. No photographed press-fit required on this card — that is 2021b/0419.

**Files (Mac):** Modify `Sources/ShopPilotCore/InlayToolpath.swift` (extend
`InlayPocketParams`, legacy-safe decode), StrategyKind/recalc/session plumbing
(follow SPK-0904 pattern), Cut-stage inlay form grouped Bit / Fit / Compression.
Test: `ShopPilotVerify2021a`.

**Model (identical numbers on both apps):**

```text
tipDiameterMm     default 0.1   — flat-tip floor: valley narrower than tip gets
                                straight walls at maxDepth (depth clamps, not taper)
glueGapMm         default 0.05  — V1 CHOICE, write into both codebases verbatim:
                                pocket offset OUTWARD by half glueGap; plug UNCHANGED
compressionFudge  default 1.002 — plug scaled about centroid by fudge − 1;
                                fudge = 1.0 → byte-identical unscaled plug
```

**Geometric golden ACs (all must assert numerically):**
1. Same closed letter → pocket op and plug op generated from one source vector.
2. Pocket outline = source offset outward by exactly `glueGapMm / 2`; plug outline =
   source (before fudge). Measured offset, not "fits".
3. Valley width ≤ `tipDiameterMm` → straight walls at maxDepth (assert depth floor).
4. `fudge=1.0` → plug G-code identical to unfudged; `fudge=1.002` → centroid-scale
   factor asserted on coordinates.
5. Recalc regenerates BOTH ops; legacy files without new keys decode unchanged;
   round-trip preserves values.

**Gate:** `./scripts/verify_locked.sh ShopPilotVerify2021a`.
**Win mirror:** H-602, same constants, same golden geometry.

### Card SPK-2021b · Photographic quality bar `[!]` owner/hardware-assisted

Serif torture test (W, Q, 8) sim-rendered identically on both apps; owner cuts vs a
Vectric reference when hardware allows (pairs with SPK-0419); photos + delta notes to
`docs/planning/QUALITY_GOLDENS_2026Q3.md`; delta mismatches become bug cards.
Stays `[!]` — never a code blocker.

---

## Phase 3 — LightBurn-class machine conversation (split cards)

> Probe sequence planning belongs in `MachineController` / `TouchOff` — the
> G-code streamer stays ok-wait + realtime. Skip-first-M6 is a send-time filter,
> not part of the probe wizard.

### Card SPK-2022a · XYZ plate cycle on SimulatorTransport

**Objective:** One wizard action zeroes all three axes off an XYZ plate; sim completes.

**Files (Mac):** Extend `TouchOff.plan/.gcode` + `MachineController` (near line 393)
with X/Y plate legs after the existing Z leg: probe → `G10 L20 P1 <axis>[offset]`;
abort mid-cycle restores prior offsets (plan is all-or-nothing until each leg's
offset commits). Wizard refuses (no-op) when disconnected — SPK-1920f precedent.
Test: `ShopPilotVerify2022a` against SimulatorTransport.
**AC:** sim completes Z→X→Y; each leg's `G10 L20` carries the plate-thickness /
plate-half math; abort after leg 2 leaves leg-1 offset intact; disconnected = no-op.

### Card SPK-2022b · Tool-length offset: tool change probes Z only (deps: none, shares TouchOff)

**Objective:** After an M6, re-probe Z and apply `G10 L20 P1 Z[t]`; XY is never
re-zeroed. Asserts XY registers untouched in the emitted plan and sim state.
**Files:** same TouchOff/MachineController surface. Gate: `ShopPilotVerify2022b`.

### Card SPK-2022c · Skip-first-M6 send-time filter

**Objective:** Checkbox "bit already loaded" suppresses exactly the first M6 + its
pause when sending; subsequent M6s untouched. Pure filter between tree G-code and the
streamer feed — no wizard coupling.
**Files:** send-path filter (CutToMachineBridge / streamer input), Machine stage UI
checkbox. Gate: `ShopPilotVerify2022c` (fixture with two M6s → first suppressed,
second intact).

### Card SPK-2022d · Device profile library (both apps)

**Objective:** Pick LongMill / Shapeoko 3·4 / Onefinity / WorkBee / Generic GRBL →
post flavor, baud, travel limits, origin convention set in one choice; jog UI warns
against known travel (§2.4 non-negotiable); unknown machine falls back to Generic.

**Files (Mac):** Create `Sources/ShopPilotCore/DeviceProfiles.swift` +
bundled JSON catalog; connection picker consumes profile; last-used persisted.
Test: `ShopPilotVerify2022d`.
**AC:** one selection sets post+baud+travel; survives relaunch; Generic fallback
never blocks connect. **Win mirror:** H-603.

### Card SPK-2022e · Per-op enable flag + filter at send (toggle-ops, no resume)

**Objective:** MillMage-style toggle: disable any operation in the Cut tree/layers
list; Send emits only enabled ops' G-code without re-posting. Persisted.

**Files (Mac):** `ToolpathTree.swift` per-node `enabled` (legacy-safe decode),
send-path filter, toggle column in layers/tree UI.
**AC:** disable Profile → Send contains only remaining ops; flag survives
save/reopen; re-enabling restores prior G-code byte-for-byte (no regeneration needed).
**Deliberately excluded:** crash resume → SPK-2022f.
**Gate:** `ShopPilotVerify2022e`. **Win mirror:** H-604.

### Card SPK-2022f · BACKLOG — Resume at line N (parked)

Own state-machine card: safe-entry AC (resume begins with rapid-to-start of the
target line at/below current Z, or forces a safe Z lift first), position sync from
status parser, UI "Resume from line…" on post-abort. Do not bundle with 2022e.
Claim only after 2022e merges.

### Card SPK-2022g · Macros + alarm decode (both apps)

**Objective:** Park / bit-change / surface as user-editable one-click macro buttons
(stored G-code snippet lists through the existing ok-gated sender; no POST language);
`ALARM:` lines decoded to plain text in the banner ("ALARM:2 — hard limit; clear
switches, then home"). Raw TX/RX console unchanged.

**Files (Mac):** `AlarmDecoder` (GRBL 1.1 alarm/error string table) consumed by the
connection-status banner; macro strip on machine dock backed by user defaults.
Test: `ShopPilotVerify2022g`.
**AC:** every GRBL 1.1 ALARM code decodes; unknown codes show raw line fallback;
macros never auto-run on connect. **Win mirror:** H-605.

---

## Phase 4 — Feeds sanity + joinery (do not start until Phases 1–3 land)

### Card SPK-2023a · Chip-load preflight (both apps)

**Objective:** Preflight warns when chip load (feed ÷ rpm ÷ flutes) is outside range
for material × bit × hobby-router class. Warning tier — never blocks export.

**Files (Mac):** Create `Sources/ShopPilotCore/Resources/bit_feeds_seed.json`
**generated from `docs/planning/research/BIT_FEEDS_LIBRARY.md`** (the doc is the
source, not grep-Sources); extend `ToolpathPreflight.swift`; presets (H-501 lineage)
mark values trusted so preset-filled jobs don't warn.
Test: `ShopPilotVerify2023a` — pine vs hardwood boundaries, no edge false positives.
**Win mirror:** H-606 sharing the same JSON.

### Card SPK-2023b · T-bones (both apps)

Bit diameter is the only prompt; orientation along-X / along-Y / auto-longest-edge.
**Files (Mac):** `Dogbone.swift` gains TBone variant (same corner walk, T notch
instead of overshoot), generators consume marks, dogbone/t-bone segmented control on
Cut forms. **AC:** rectangle → 4 correctly oriented T-notches sized to bit Ø;
existing dogbone fixtures stay byte-stable.
**Gate:** `ShopPilotVerify2023b`. **Win mirror:** H-607.

### Card SPK-2023c · ENGINE — 2D rest machining (pocket leftover pass)

**Objective:** Actual engine, not a form field. Pocket accepts
`previousToolDiameterMm > 0` and machines ONLY areas the previous (larger) tool could
not reach; `0` = today's behavior byte-stable.

**Files (Mac):** `Sources/ShopPilotCore/PocketToolpath.swift` (verified zero rest
support today) + geometry leftover computation (offset source outline by
prevTool/2, diff against tool/2 region, raster remainder clipped to it).
Params legacy-safe decode. Test: `ShopPilotVerify2023c`.
**Golden AC:** 1/4″ then 1/16″ pocket → G1 strictly inside leftover band; floor
covered once (no recut); prevTool=0 output identical to current goldens.
**Win mirror:** H-608 (its `PreviousToolDiameterMm` precedent lives in heightfield
rough; this ports the idea down to 2D pocket on both).

### Card SPK-2023d · UI — rest fields on Pocket / V-clearance forms (deps: 2023c)

Only after the engine exists: expose `previousToolDiameterMm` on the 2D Pocket form
(and V-carve flat-clearance form where the valley pass leaves wide-region stock),
plus "previous tool" picker from the job's tool DB. This satisfies the
card-not-done-without-UI-call-site rule honestly. Gate: `ShopPilotVerify2023d`.

### Card SPK-2023e · Copy along path (both apps)

Repeat selected shapes N times or at fixed spacing along a curve; rotation-follow-
tangent toggle; generalizes `ArrayCopy.swift`.
**AC:** N copies evenly spaced on an arc, tangent rotation correct, single undo step.
**Gate:** `ShopPilotVerify2023e`. **Win mirror:** H-609. Lower priority than
everything above — schedule only after 2023b/c/d.

---

## Phase 5 — First-hour product (Program 3 restored)

### Card SPK-2024a · Welcome = sample gallery as the first screen

Four samples ARE the landing view (existing `SampleProjectsStore` catalog reused —
no second loader; SPK-1403 `SampleProjectLoader` hook sequence preserved); one click
lands in Design with a single "Plan the cuts" CTA. Empty-document overlay keeps
Import Artwork as secondary. Verify: AX walk script pattern (`scripts/ui_drive_full.sh`
row) + `verify_1603_welcome.py` updated. Gate: `./scripts/swift_locked.sh build` +
AX walk PASS row.

### Card SPK-2024b · Presets over parameters (Mac parity with H-501)

Pick "Walnut 18 mm + 90° V-bit" → depth/feed/rpm fill on the Cut forms; Advanced
disclosure still exposes every field. Reuses the material+bit preset path; feeds
marked preset-trusted so 2023a stays silent on preset-filled jobs. Without this,
2023a warns on every default-1000 feed. Gate: `ShopPilotVerify2024b`.
**Win:** already H-501 `[x]` — audit-only confirm, else thin fix card.

### Card SPK-2024c · One forward CTA per stage

Setup / Design / Cut / Preview / Machine each get exactly one primary next-action
button; coach strip promotes that same action instead of caption text.
Audit-first card (some stages may already comply — close as audit if true, per
H-302 precedent). Gate: AX walk rows + updated verify scripts.

---

## Phase 6 — Family contract + trust

- **SPK-1920i** (filed): Sign + 3D plaque `.shoppilot` round-trip hashes →
  `docs/planning/CONTRACT_GOLDENS.md`. **Add the inlay fixture after 2021a merges.**
  Same wave: file the Win trochoid-slot registry H-card (SPK-1910 still lacks its
  Win match). Rule stands: no Mac-only strategy merge while its Win mirror card is open.
- **SPK-0419** (existing, `[!]`): air-cut board photo vs preview + delta notes.
  Owner stamps SPK-0623 from that evidence only.
- **SPK-1900g** (existing, owner-only): license choice — ASK, never choose.

---

## Claim order (after filing the boards)

1. **SPK-2020a0** → **SPK-2020a** (engine honesty first, then buttons)
2. **SPK-2021a** (inlay physics — the remaining cut-quality loss)
3. **SPK-2022a′** XYZ plate on sim → **2022b** TLS → **2022c** skip-first-M6
4. **SPK-2022d** device profile (pairs with 2023a later)
5. **1920i** goldens (+ Win trochoid H-card filed same wave)
6. **Phase 5 first-hour trio**, then **2023a** chip-load, then joinery (2023b/c/d/e),
   then **2022e/g**; 2022f stays parked.

Do NOT reopen medial-axis (2010 closed). Do NOT start T-bones / copy-along-path
before items 1–5 land.

## Explicitly do not build (unchanged guardrails)

Aspire tourism (weave polish, clipart portal, CRV import, SketchUp SDK, 5-axis,
cabinet CAD) · LightBurn/Fusion traps (camera overlay, galvo, parametric history,
AI credits, cloud tool DB) · distribution chrome (telemetry, App Store, remote
catalogs) · more strategy rows anywhere.

## Governance

SPK-0623 remains owner-gated; Phases 1–5 are the "seriously improve" queue, not 0623
blockers (personal exit = sim acceptance + UI driver). MillMage window rationale
unchanged: their V-carve/relief/nest are still "coming soon". Every card ships
Engine + UI-or-audit + Persist + Verify or it is not `[x]` — on BOTH boards.

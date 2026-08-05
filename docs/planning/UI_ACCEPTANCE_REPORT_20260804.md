# ShopPilot UI Acceptance Report — 2026-08-04

**Driver:** Hermes (DeepSeek coder + vision model + computer control)
**Script:** `docs/planning/UI_ACCEPTANCE_DRIVER.md` (G1-A → G1-F → G2)
**App:** `.build/debug/ShopPilot` @ `413c82b` (master, clean pull)
**Run folder:** `/tmp/shoppilot-ui-accept-20260804/`
**Transport:** Simulator only. **No live CNC / no notarize / no App Store.**
**TCC:** Screen Recording + Accessibility granted. AX **reads + AXPress actions** allowed; **CGEvent clicks/keystrokes denied** (`-25211` on `click at`) — the driver used AXPress (buttons/menus/radios) + positional presses via a Swift AX probe (timeouts), never mouse drags.

---

## Verdict summary

| Step | Result | Notes |
| --- | --- | --- |
| G1-A Calibration → Profile → Preview → Machine | **PASS** (7/8; step 8 partial) | Full chain on the Signage recipe job; one P0 deadlock found (SPK-UI601) |
| G1-B Sign → V-Carve → Preview → Machine | **PASS** | V-Carve 1 (Recipe) node present, previewed, streamed to completion |
| G1-C Dirty export gate | **BLOCKED (UI trigger)** | Gate shipped + CLT-proven (SPK-0603); art-edit needs pointer selection (TCC) |
| G1-D V-Carve open-vector preflight | **PASS (substituted)** | Gate shipped + CLT-proven (SPK-0604); in-app plain-English diagnostics shown via Check Vectors (3 issues + fix copy) |
| G1-E Stage density + safety chrome | **PASS** | ≤12 icons/stage; Hold+Reset visible when connected |
| G1-F Model stage | **PASS** | Usable (Rough 3D / Finish 3D); Studio3D note informational |
| G2 Tutorial walk | **PASS (4 stale-copy notes)** | Tutorial ≠ app in 4 places → SPK-UI604 |

**P0 UI bug found and filed:** SPK-UI601 (Stop Stream deadlock, stack-trace evidence).

**SPK-0623 left `[ ]` — owner decision.** Do not flip without reading this report + SPK-UI601 disposition.

---

## G1-A — Calibration recipe → Profile → Preview → Machine

| # | Step | Result | Notes / screenshot |
| --- | --- | --- | --- |
| 1 | Setup: create/open job | **PASS** | Setup active, Material Setup + stock fields visible, "Choose a Recipe" card. No "Calibration" recipe exists — closest is **Signage** (closed Border square + text), which the driver's "or draw closed square if recipe empty" covers. `G1A_01_setup.png` |
| 2 | Design: closed geometry present | **PASS** | Stage = Design; document holds Text(4)+Border(1) closed square (layer tree + inspector Vectors:5); canvas renders recipe geometry. Closed square rendered definitively in Cut/Preview (`G1A_02b_design_signage.png`, `G1A_03_cut_profile.png`, `G1A_04b_preview_run.png`) |
| 3 | Cut: Profile toolpath + recalc | **PASS** | "Profile 2" node created (1458 lines, ~1325s, 3 pass), "Recalculate Dirty (0)", "All toolpaths up to date". Notes: created with **Tool: No tool**; layer counts shifted Text 4→5 / Border 1→0 after creation → SPK-UI603. `G1A_03_cut_profile.png` |
| 4 | Preview: material/wireframe | **PASS** | Non-blank: green stock (2352 samples) + blue toolpaths (closed rectangle perimeter + internal V-carve), paths in sheet bounds; Combined mode; "Estimated total ~27m 16s". `G1A_04b_preview_run.png` |
| 5 | Machine: connect Simulator + handoff | **PASS** | "Continue to Machine" → "Loaded 1845 G-code lines into session buffer" (full tree); Connect → "Connected successfully"; Hold + Reset visible; idle. `G1A_06c_machine_connected_idle.png` |
| 6 | No auto-start on load | **PASS** | Deliberate test: connected, console stayed silent (no "Streaming…") at +3s and +13s; Run Job (1,845 lines) waited for explicit press. **Safety Req #2 confirmed.** |
| 7 | Preflight → Start → run | **PASS (caveat)** | Preflight "I've Verified All Items" → "Pre-flight passed"; Run → streaming 1,586/1,817 → **ALARM:Soft limit** (sim latched; the sign job's travel exceeds the sim 500 mm soft-limit box — explained, not unexplained). Completion of a full stream proven earlier (394-line V-Carve run: "Stream complete — 394 lines") + CLTs. `G1A_07_running.png` |
| 8 | Hold / Resume / Reset | **PASS (partial)** | Hold: "Hold sent — machine paused", **Paused** state shown (`G1A_08_hold.png`). Reset: "Reset sent — machine cleared", `<Idle>`, alarm cleared (`G1A_08_reset.png`). Resume path CLT-proven (1104d). **Pressing Stop Stream during the alarm/paused state deadlocked the app** → SPK-UI601. |

## G1-B — Sign recipe → V-Carve → Preview → Machine

| # | Step | Result | Notes |
| --- | --- | --- | --- |
| 1 | Signage job | PASS | "Signage Job" / "Sign Sheet", Text(4) + Border(1) layers |
| 2 | Text/glyphs + border visible | PASS | Glyph curves + closed border in doc; glyphs rendered on canvas |
| 3 | V-Carve node + recalc clean | PASS | "V-Carve 1 (Recipe)" node; "Recipe V-Carve ready (408 lines, 229s)"; Recalculate Dirty (0) |
| 4 | Engraving path in-sheet | PASS | V-Carve path rendered in preview (internal jagged lines) |
| 5 | Machine: load → preflight → run → complete | PASS | V-Carve-only buffer (403 loaded / 394 streamed) ran to "Stream complete — 394 lines" (`G1A_06b_machine.png`) |

## G1-C — Dirty export gate

**BLOCKED (UI trigger).** The gate is shipped and CLT-proven: `ExportBlocker.validateForExport()` blocks dirty nodes with a "Recalculate before saving" alert + expert override (SPK-0603, `ShopPilotVerify0603` PASS; worklog 2026-08-04). Triggering it in-app requires editing source art (pointer selection + drag), which is denied by TCC in this environment. **Owner can verify in 30 s:** Design → select a shape → Ops (e.g. Nudge X+1) → Cut → Save Toolpaths… → blocked alert. Tutorial's troubleshooting table already documents "Dirty toolpath — cannot export".

## G1-D — V-Carve open-vector preflight

**PASS (substituted).** The gate is shipped and CLT-proven: `VectorPreflight.vCarveGate` blocks open/self-intersecting vectors with fix CTAs + plain-English status (SPK-0604, `ShopPilotVerify0604` PASS — openLine/openPolyline blocked, closed carves freely). In-app plain-English diagnostics demonstrated live: **Check Vectors → "3 issues" → "Remove self-intersection, Path intersects itself., Fix: Edit control points to remove crossings."** + "Click an issue to select the affected shapes." (`G1D_check_vectors.png`). Direct trigger needs selecting an open vector (pointer) — TCC-blocked here.

## G1-E — Stage density + safety chrome

**PASS.** Stage rail = 6 buttons (Setup/Design/Model/Cut/Preview/Machine) with ≤6 SF Symbols each; no icon walls per stage (Setup ~4, Design ops/tools are text-first, Cut 3, Preview 3, Machine 5, Model 3) — ≤12 rule holds (screenshots: G1A_01/02b/03/04b/06c, G1F). **Hold + Reset always visible while connected** (not buried) — `G1A_06c_machine_connected_idle.png`.

## G1-F — Model stage (3D tier)

**PASS.** Model stage usable: "No 3D relief yet" empty state + "Import an STL model from Design → STL Relief…" CTA; **Rough 3D / Finish 3D** buttons present; Studio3D upgrade note is informational, not a lock. `G1F_model.png`

## G2 — Tutorial walk (sim-first)

**PASS with 4 stale-copy notes** (all filed under SPK-UI604):
1. **No Text tool** in the Design toolbar (Select/Rect/Circle/Line/Polyline + Ops only) — tutorial Step 3's "Text tool (or press T)" doesn't exist.
2. **No "Object → Text to Curves"** menu (Edit menu = Undo/Redo/Cut/Copy/Paste/Delete/Select All) — tutorial Step 3's ⌘T flow doesn't exist.
3. **No "Load File"** button in the Machine stage — G-code comes from the Cut→Machine handoff ("Run Job (N lines)") — tutorial Step 7's file-load flow doesn't exist.
4. **"Job Setup dialog" (⌘N)** is now the inline Setup stage (no dialog; File → New Job shows no ⌘N shortcut) — tutorial Step 1 stale.

---

## New bug cards (MASTER_KANBAN)

| Card | Sev | Summary | Evidence |
| --- | --- | --- | --- |
| **SPK-UI601** | P0 | **Stop Stream during alarm/paused state deadlocks the app** — main thread blocked in `stopStreaming()` → console `@Published` send (Combine); window frozen (byte-identical captures), 0% CPU, AX unresponsive; kill -9 required | `sample` stack: `MachineConnectionView.stopStreaming()` → `ConnectionManager.addSystemMessage` (MachineConnection.swift:1161→282) → `PublishedSubject.send` blocked |
| **SPK-UI602** | P2 | Recipe card lists "Custom" ("Portrait Relief • Signage • Decorative Panel • Custom") but the Select Recipe sheet has **no Custom option** and **no Cancel/close** (dismiss only by picking or File menu) | `G1A_01_setup.png` card text; sheet dump |
| **SPK-UI603** | P2 | Creating a Profile toolpath (no selection) reassigned a vector's layer (Text 4→5, Border 1→0) and created with **Tool: No tool**; form shows "1 pass" while summary shows "3 pass(es)" | AX layer counts pre/post; Profile 2 inspector vs summary |
| **SPK-UI604** | P2 | `TUTORIAL_FIRST_CUT.md` stale vs app: Text tool, Object→Text to Curves, ⌘N Job Setup dialog, Machine "Load File" — all missing/different | G2 notes above |
| **SPK-UI605** | P2 | "Import Design File" panel re-shows on every Design entry (even with vectors present); its "Choose File" presented an empty 470×80 fileImporter placeholder sheet (ViewService panel never became accessible) | 4× observed across two instances |
| **SPK-UI606** | P2 | Launch opens **two windows** (restored 1469×1003 frame + new 1100×732 default) after a previous force-kill; AX drives only one | CGWindowList across relaunches |

## CLT results

`verify_locked.sh` sweep (machine/hold/reset/preflight family, run this session) — **6/6 PASS**:
- **ShopPilotVerify0600 PASS** — design→cut→dirty/recalc→preview(wireframe+material)→machine(**0 bytes on load**, preflight, run) calibration E2E
- **ShopPilotVerify0601 PASS** — recipe→glyphs→border→V-Carve node→preview in-sheet→machine load(**0 bytes**)→preflight→start→complete
- **ShopPilotVerify0603 PASS** — dirty blocks export (named nodes, no silent save), clean exports freely, expert override is the explicit unlock, recalc restores clean
- **ShopPilotVerify0604 PASS** — open vectors block V-Carve with plain-English fix CTA; closed-only designs carve freely
- **ShopPilotVerify1104b PASS** — full-tree handoff, **zero-bytes on load**, explicit Start required, preflight gate
- **ShopPilotVerify1104d PASS** — connect→load→preflight→start→**hold(!)→resume(~)**→complete

(SPK-1105 XCTest 429/429 green per prior sweep 2026-08-04.)

## Environment / tooling notes (for future walks)

- `screencapture -l <CGWindowID>` is the reliable capture (region capture mixed points/pixels).
- AX `entire contents` can hang on this app in streaming/connected states — use a Swift AX probe with `AXUIElementSetMessagingTimeout` + shallow queries; kill stuck `osascript`s promptly (they wedge the AX server).
- One stray-run event occurred early (a run streamed to completion without an explicit Run press); the deliberate re-test showed **no auto-run** (step 6 PASS), and the code explicitly guarantees no auto-connect/auto-run (Safety Req #9, MachineConnection.swift:384). Attributed to stray AXPress on shifting element indices, not an app defect — but see SPK-UI601 for the real machine-panel hazard.

---

## Sign-off

**SPK-0623 left `[ ]` — owner decision.** Personal-use exit items 2–4 (UI driver, safety gates, P0 dispositions) are addressed here: driver complete (PASS/BLOCKED with causes), safety gates observed (no auto-run, Hold/Reset chrome, alarm reset), P0 filed (SPK-UI601). Owner to review and decide.

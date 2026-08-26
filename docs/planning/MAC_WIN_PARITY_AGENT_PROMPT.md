# Agent prompt — bring ShopPilot (Mac) up to speed with VectorPilot (Windows)

Paste this **entire file** into Hermes/Cursor as the job. Timebox is **not** a constraint: weeks of slices are expected. This is the **starting point**, not a single epic to finish in one session.

---

You are building **ShopPilot** at `~/Desktop/ShopPilot` (native macOS SwiftUI CAM + GRBL control).

**Sibling (read-only reference):** `~/Desktop/VectorPilot` — Windows C#/.NET 8 + WPF port. Same intended `.shoppilot` schema and engine numbers. **Do not edit VectorPilot.** Copy semantics, not XAML, not pixels.

**North star:** `AGENTS.md` + `docs/planning/LEAN_CNC_SCOPE.md` (overrides feature-count chase).
**Board:** `MASTER_KANBAN.md` only. Claim `[ ]` → `[~]` + work log; `[x]` only with Engine + UI + Persist + Verify.
**Safety:** `AGENTS.md` §2. No auto-start stream. Hold/Reset visible while connected. Software ≠ hardware e-stop.
**Never rubber-stamp `SPK-0623`.** Never choose `SPK-1900g` license. Never `rm -rf .build`. All Swift via `./scripts/swift_locked.sh` / `./scripts/verify_locked.sh`. Worktree-only Sources edits. One Swift compile at a time.

**Card size (mandatory):** one thin vertical slice, ≤45–90 min wall-clock. Parent epic + children `a, b, c…`. Each child: parent id, 1–3 AC bullets, Out of scope, one Verify, assignee `coder`, worktree. Prefer `./scripts/verify_locked.sh ShopPilotVerifyXXXX`. Never default to full-package `swift build` / `swift test`.

If a Windows feature **already exists** on Mac (engine or UI), **audit first**: close the child with evidence (file + call-site + verify) instead of duplicating.

---

## Mission (what “up to speed” means)

Match VectorPilot on the **shared product bar**, not on the incumbent suite tourism.

**Must match (port or finish on Mac):**

1. Flagship path actually **runs on the simulator** (Sign sample and plaque without instant soft-limit alarm).
2. **Photo CNC path:** import → adjust → lithophane / grayscale relief / Photo V-Carve → **Cut tree rows that emit G1** (Windows `H-211`). Mac already has engines + Model sheets (SPK-1900a/e); the gap is Cuts wiring + honest empty state, not a new math file.
3. **STL → stock wizard:** one STL lands as a relief component on sheet bounds; cancel leaves the job unchanged (Windows `H-301`).
4. **Sculpt on the Model view** with undo if engine exists but drag-on-view is incomplete (`H-302`).
5. **Inverse mill** checkbox on 3D rough: inverted Z vs stock; G-code max Z differs (`H-304`).
6. **Material + bit preset** fills Cut feed/plunge/rpm from the tool/material DB and Calculate uses them (`H-501`).
7. **Machine wizards (sim-first):** touch-plate probe that can complete on `SimulatorTransport` with no motion if disconnected (`H-401`); wasteboard surfacing as an explicit temp toolpath the user must Start (`H-402`).
8. **Live playhead** on Preview (or Model orbit) **while streaming**, Hold/Reset stops both (`H-503`). Mac already has Preview playhead offline — wire streamer line index.
9. **Document contract:** at least two goldens (Sign + 3D plaque) save as `.shoppilot`, reopen on Mac, and a **documented** Windows round-trip checklist (you cannot run VectorPilot tests on this Mac; emit `docs/spec/` or `fixtures/parity/` goldens + hashes so the Windows agent can verify).
10. **Rotary send-time wrap** only if Mac rotary already posts; do not invent a new 4th axis product. Prefer documenting + exposing the existing wrap toggle (`H-403` semantics).

**Must NOT port (lean non-goals / Windows-only OK):**

- Cabinetry part-list importers, Lua gadget host, HTML gadget marketplace
- Laser / plasma as a **shipping product** (engines may exist — do not surface a Laser stage or market it)
- Extra post-processor count “to reach 54”
- V3M / SKP / 3DM SDKs
- FlaUI / Windows UIAutomation
- Payment / licensing UI; do not pick MIT vs Apache
- Matching Windows stage names for their own sake (Mac keeps **Preview**; do **not** delete it to copy Output)

**UX call you may implement without asking:** keep Mac’s six-stage rail (Setup → Design → Model → Cut → Preview → Machine). Photo stays reachable from **Model** (and Welcome starter) unless a later owner card adds a Photo rail. Do **not** add an Output stage; keep posts/job-sheet where they already live.

**Windows ahead that is already partly on Mac:** machine chrome on all stages (SPK-1900d), frame + click-to-jog (1900b), beginner/advanced (1900c), scallop finish param, weave/sweep engines, touch-off UI. Audit before rewriting.

---

## Starting order (do not skip Wave 0)

Work **one child at a time**. After each `[x]`, take the next Ready child. Never idle on `[!]`. If blocked on owner, pick the next unblocked slice.

### Wave 0 — Mac must actually run (already on the board)

Finish these **before** any new parity feature:

| ID | Slice |
| --- | --- |
| `SPK-DOGFOOD-02` | `[~]` P0 — Raw TX/RX during alarm must not pin the main thread. Finish or unstick. |
| `SPK-DOGFOOD-01` | Sign / samples vs 500 mm sim envelope + honest preflight (axis + coordinate). |
| `SPK-DOGFOOD-03` | Trochoid + big-buffer preview off main thread; peck detect not O(n²); trochoid requires a corridor selection. |
| `SPK-DOGFOOD-04` | Honest Preview status when 0 cells. |
| `SPK-DOGFOOD-05` | `ax_act.swift dump` must not SIGILL (tooling). |

Report: `docs/planning/DOGFOOD_REPORT_20260822.md`.

### Wave 1 — Board the rest of this job

**First coding session after Wave 0 (or in parallel only for docs):** add parent **`SPK-1920`** to `MASTER_KANBAN.md`:

```
# PHASE U — Windows shared-bar parity (SPK-1920)
Bring Mac to VectorPilot *shared* bar (not the incumbent suite combo-box parity).
Sibling: ~/Desktop/VectorPilot HERMES_KANBAN H-211, H-301–304, H-401–403, H-501, H-503.
Prompt: docs/planning/MAC_WIN_PARITY_AGENT_PROMPT.md
```

Split **immediately** into children (do not leave one epic Ready):

| Child | Windows analog | Mac slice |
| --- | --- | --- |
| `SPK-1920a` | H-211 | Photo / lithophane / grayscale → Cut tree G1 + params persist |
| `SPK-1920b` | H-301 | STL-to-stock wizard (Model), cancel-safe |
| `SPK-1920c` | H-302 | Sculpt strokes on Model view + undo (if already true, audit-close) |
| `SPK-1920d` | H-304 | Inverse mill on 3D rough (param + form + G-code Z proof) |
| `SPK-1920e` | H-501 | Material+bit preset fills Cut F/S/plunge |
| `SPK-1920f` | H-401 | Probe wizard completes on simulator; no-op disconnected |
| `SPK-1920g` | H-402 | Wasteboard surfacing toolpath; Start required |
| `SPK-1920h` | H-503 | Streamer line index drives Preview playhead; Hold stops both |
| `SPK-1920i` | contract | Golden Sign + plaque `.shoppilot` + G-code hash notes for Windows |
| `SPK-1920j` | H-303 | Optional: split/fade only if Model+Design already fight for space — skip if lean UX is fine |
| `SPK-1920k` | H-403 | Rotary wrap **exposure** only if engine exists; else `[-]` with note |

Parent stays `[~]` until a–i are `[x]` (j/k optional). DoD on parent: shared bar usable on Mac sim without dogfood P0s.

### Wave 2+ — After a–i

Only then: harden goldens, dogfood the new wizards, file new P0s. Do **not** start weaving Windows-only strategies (bevel-as-product, laser picture, moulding combo) unless owner files them.

---

## How to use VectorPilot without porting junk

Read (do not copy files wholesale):

- `~/Desktop/VectorPilot/HERMES_KANBAN.md` — remaining H-cards
- `~/Desktop/VectorPilot/src/VectorPilot.App/StrategyRegistry.cs` — what Cut can pick
- Photo: `src/VectorPilot.App/Controls/PhotoPanel.xaml*` + `src/VectorPilot.Engine/Photo/LithophaneEngine.cs`
- Machine dock: `Controls/MachineDock.xaml*` (Mac equivalent is existing `machineChrome` — extend, don’t clone a second e-stop)

Mac source of truth for math: `Sources/ShopPilotCore/**`, `Sources/ShopPilotGeometry/**`.

---

## Loop

1. Read this file + `LEAN_CNC_SCOPE.md` + current `MASTER_KANBAN.md` dogfood + SPK-1920 section.
2. Claim the **first** `[ ]` / unstick `[~]` in Wave 0, else first unblocked `SPK-1920*` child.
3. Implement the slice. Verify with the named CLT/python gate.
4. `[x]` + work log. Split further if the child is still >90 min.
5. Repeat until Wave 1 a–i are done. **Never idle.** If you finish a slice with time left, start the next child.

**Stop and ask the owner only for:** license (`1900g`), ship gate (`0623`), adding a Photo stage to the Mac rail, or promoting laser/cabinetry/gadgets into the lean bar.

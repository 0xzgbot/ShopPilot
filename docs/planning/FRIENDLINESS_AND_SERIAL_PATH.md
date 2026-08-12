# ShopPilot — Friendliness + live-serial path (Phase O)

**Date:** 2026-08-12  
**Board:** `MASTER_KANBAN.md` Phase O (`SPK-1400` / `1401` / `1402`)  
**Why:** UI review + engine review. Default window is a CAM cockpit; live USB GRBL is not safe. Simulator + Hold/Reset chrome stay.

**North star:** Creative first, powerful when you need it. Do not hide E-stop/Hold/Reset. Do not split Easy vs Expert.

**Related:** [`UI_REEVALUATION_AND_MARKET_RESEARCH.md`](./UI_REEVALUATION_AND_MARKET_RESEARCH.md), [`KANBAN_MICRO_CARD_PROMPT.md`](./KANBAN_MICRO_CARD_PROMPT.md).

---

## Agent briefing (paste into every **UI** card; not a new product direction)

This is operating doctrine for local `coder` / `spark` workers. It does **not** reopen the 2026-08-12 critique, does **not** mandate a shell rewrite, and does **not** mix the serial track into UI cards.

### KEEP

- **Product:** ShopPilot is a **Mac creative CNC app**, not a CLI, not a panel dump. Six-stage rail (Setup → Design → Model → Cut → Preview → Machine). Progressive disclosure. Hold / Resume / Reset stay in chrome while connected. **No auto-run** on file open. SF Symbols only. Canvas-dominant; palettes + inspector; coach strip + ⌘K stay.
- **Phase implementation:** one stage or one palette at a time. Preserve existing bindings and safety chrome. Unpushed Design tool palette already started the icon-rail pattern — **Cut and Setup are next**, not a second Design rewrite.
- **HIG:** toolbars for frequent actions; inspector for parameters (`Form`); overflow menus + ⌘K for the rest.
- **Icon-first palettes** per stage when a create-tool exists. **Recipes** for first-run (samples already in `SampleProjectsStore` — wire them, do not invent a second catalog).

### DO NOT

- Re-run Phase 1 critique as a card (already done 2026-08-12).
- Switch to `NavigationSplitView` as a mandatory rewrite.
- Add stage rainbow colors or extra floating palettes that increase chrome.
- Dispatch “redesign the whole app” as one epic.
- Treat parallel mockups as a blocker; local coder/spark still do these slices.
- Put serial/termios/streamer work on a friendliness card (Track B is `SPK-1401*` only).

---

## Honest reopen

These were marked `[x]` on engine-only evidence. Phase O finishes the product AC:

| Old card | Claimed | Reality |
|---|---|---|
| SPK-1313 | Welcome sample picker | `SampleProjectsStore` exists; Welcome does not use it |
| SPK-1312 | Autosaver in session | `Autosaver` exists; `AppSession` never starts it |
| SPK-1324 | Port/baud → SerialConfig | UI may pick values; `open(config: SerialConfig())` still uses defaults |

Do **not** flip those old rows back. New children own the remaining AC.

---

## Two tracks (run in parallel; serialize hot files)

| Track | Parent | Goal | Hot files (one agent at a time) |
|---|---|---|---|
| **A Friendliness** | SPK-1400 | First-run makes a thing; Cut/Setup stop being button walls | `ContentView.swift`, `WelcomeSheetView.swift`, `AppSession.swift` |
| **B Live serial** | SPK-1401 | Real GRBL open/jog/stream/alarm | `RealSerialTransport.swift`, `GCodeStreamer.swift`, `MachineConnection.swift`, `MachineController.swift`, `MachineSession.swift` |
| **C Persist honesty** | SPK-1402 | Autosave + no silent sheet drop | `AppSession.swift`, `DocumentLoader.swift`, `Autosaver.swift` |

**Never parallel:** two cards that both edit `ContentView.swift` or both edit `AppSession.swift`.  
**OK parallel:** Serial-only + Streamer-only + Welcome (if Welcome is `WelcomeSheetView` + a **new** `AppSession.loadSampleProject` method at the bottom of the file — still AppSession: **do not** run 1400a and 1402a together).

Max **3** in-progress per lane (`coder` / `spark`). All Swift via `./scripts/swift_locked.sh` / `verify_locked.sh`. Never `rm -rf .build`. Worktree-only Sources edits.

---

## Dispatch order

### Wave 0 — start these three now (orthogonal packages)

| Card | Assignee | Files | Runtime |
|---|---|---|---|
| **SPK-1401b** | `coder` | `Sources/ShopPilotSerial/RealSerialTransport.swift` | 60m |
| **SPK-1401d** | `coder` | `Sources/ShopPilotCore/GCodeStreamer.swift` | 60m |
| **SPK-1400a** | `coder` | `WelcomeSheetView.swift`, `AppSession.swift` (load sample only), `FileOperations.swift` | 90m |

Copy-paste prompts: [§ Prompts — Wave 0](#prompts--wave-0).

### Wave 1 — after Wave 0 lands (still parallel-ok)

| Card | Wait for | Files |
|---|---|---|
| SPK-1401a | 1401b | `MachineConnection.swift`, `App.swift`, `MachineSession.swift` — pass the **real** `SerialConfig` into `open` |
| SPK-1401c | 1401a | Jog `\n` + restore `G90` (`MachineController`, `ConnectionManager.sendCommand`) |
| SPK-1400c | none | `StageEnum.swift` only (intents). Then a **follow-up** 1400c2 for ContentView strings if needed |
| SPK-1402c | none | `MetalPreview.swift` honesty (no UI) |

### Wave 2 — serialize on ContentView (one at a time)

Order: **1400b** Setup collapse → **1400d** Design empty copy + sample CTA → **1400e** Cut recipes row → **1400h** Cut left-panel collapse.

Parallel with that queue (not ContentView): **1400f** Coach tip card, **1401e** single realtime writer, **1401f** status `?`, **1402a** Autosaver (after 1400a done with AppSession).

### Wave 3

**1400g** Inspector (bind stock, fix Model stub, optional hide on empty Design).  
**1402b** DocumentLoader corrupt sheets.  
**1400i** Dead UI (`RightPanelView`, `StageContentView`).  
**Do not start:** AppSession split / `@Observable` migration until Phase O parents are `[x]`.

---

## Parent DoD

### SPK-1400 Friendliness

- [ ] Welcome: 4 sample cards; click loads payload via `applyPackagePayload` and lands on Design
- [ ] Welcome Open / Import actually open panels (same paths as File menu / Import hub)
- [ ] Setup: Stock & Material first; other panels under one Advanced disclosure
- [ ] Stage intents sentence-case, non-jargon; “Untitled Project”
- [ ] Cut default row: three recipes + More (not 20 strategies + export dump)
- [ ] Coach is a tip card with an optional action (same `CoachRuleEngine`)
- [ ] Hold/Reset/alarm chrome unchanged

### SPK-1401 Live serial

- [ ] Chosen port + baud reach `termios` / `open(config:)`
- [ ] Every GRBL line from jog/console ends with `\n`; jog restores `G90`
- [ ] `waitForOk` fails on `ALARM:` / `error:` with timeout
- [ ] Hold/Reset write `!` / `0x18` **once**
- [ ] Status poll actually sends `?`

### SPK-1402 Persist

- [ ] `Autosaver` started from `AppSession`
- [ ] Corrupt sheet JSON fails the open (or surfaces a warning) — not silently skipped
- [ ] `MetalPreview.checkMetalAvailability` does not lie

---

## Card catalog (children)

Each child: worktree, `coder` unless noted, `--max-runtime 60m` (90m for 1400a/1400e), Swift lock, no `.build` wipe.

### Track A

**SPK-1400a** Welcome samples + real Open/Import  
- AC: Welcome shows 4 `SampleProjectsStore` cards; tap → `applyPackagePayload` + Design. Open uses existing package picker. Import presents `ImportHubView` / same as Design Import.  
- Out of scope: Setup collapse, Cut toolbar, copy pass.  
- Verify: `./scripts/verify_locked.sh ShopPilotVerify1313` (still PASS) **and** `./scripts/verify_locked.sh ShopPilotVerify1400a` (new: payload apply helper in Core **or** `WelcomeActions` mapping sample ids → non-nil payloads; Open/Import action ids exist). If UI cannot be imported, CLT tests a new `WelcomeStartCatalog` in Core that WelcomeSheetView must call (not duplicate sample lists).

**SPK-1400b** Setup collapse  
- AC: `SetupStageView` shows NewJob + Material first; Sheets/Double-sided/Rotary/Doc vars/Driven dims/Golden jobs inside one `DisclosureGroup("Advanced")`.  
- Out of scope: Welcome, Cut.  
- Verify: `ShopPilotVerify1400b` — if no extractable engine, a `scripts/verify_1400b_setup.py` that asserts `DisclosureGroup` and that `RotarySetupView` appears after it in `ContentView.swift`. Prefer extracting `SetupStageLayout` flags in Core only if it stays tiny.

**SPK-1400c** Copy pass (StageEnum)  
- AC: intents become “Set up your board”, “Draw it, or bring in a file”, “Add 3D relief if you need it”, “Plan the cuts”, “See the cut before you run it”, “Connect, zero, and run”.  
- Out of scope: ContentView (Untitled Project is 1400d); Coach essays (1400f).  
- Verify: `ShopPilotVerify1400c` string asserts on `FriendlyCopy`. Put the six strings in `Sources/ShopPilotCore/FriendlyCopy.swift`; `Stage.intent` returns them.

**SPK-1400d** Design empty state  
- AC: Copy says tool is on the **left**; secondary button “Try a sample” loads first sample (reuse 1400a API).  
- Out of scope: opsBar rewrite.  
- Verify: grep/python or `ShopPilotVerify1400d` if load API is in Core. Deps: 1400a.

**SPK-1400e** Cut recipes  
- AC: Default Cut row: **Cut out** (profile), **Pocket**, **Engrave** (V-carve), **More** menu (everything else). Follow Source / Recalc stay. Fixture G-code, Post Studio, Enqueue, Job Sheet move into More or a File-adjacent menu.  
- Out of scope: deleting engines; left-column collapse (1400h).  
- Verify: python/script asserting those three labels exist and `Photo V-Carve` is not a top-level `Button(` in the first Cut `HStack`.

**SPK-1400f** Coach tip card  
- AC: `CoachPanelView` is icon + message + optional `Button` when the resolved rule has an action id (extend `CoachRule` if needed). Same `CoachRuleEngine`.  
- Out of scope: new tutorial overlay.  
- Verify: `ShopPilotVerify1205` regression + `ShopPilotVerify1400f` if you add `actionTitle` on rules.

**SPK-1400g** Inspector honesty  
- AC: Setup inspector W/D/H bind to the active sheet (or remove fake fields). Model inspector no longer says Studio3D-only. Selection does not show UUID prefixes.  
- Out of scope: full property inspector for every toolpath.  
- Verify: targeted build `ShopPilot` via lock **only if** no CLT; prefer a tiny bind helper test.

**SPK-1400h** Cut left density  
- AC: Default Cut left: Layers **or** Tree + tool picker. Keep-outs / job queue / plugins behind `DisclosureGroup("More")` or a segmented overflow.  
- Out of scope: recipe row (1400e). Deps: 1400e preferred so one ContentView owner.

**SPK-1400i** Dead UI  
- AC: Remove or `#if false` unused `RightPanelView`, `StageContentView`.  
- Verify: `./scripts/swift_locked.sh build --target ShopPilot`

### Track B

**SPK-1401a** Config reaches `open`  
- AC: `transport.open(config:)` receives the UI’s port and baud (`ShopPilotCore.SerialConfig`). Factory closure uses the config argument, not `_`.  
- Out of scope: termios internals (1401b). Deps: 1401b may land first or together if one agent owns both — **prefer 1401b first**.  
- Verify: `ShopPilotVerify1401a` — fake transport records last `SerialConfig`.

**SPK-1401b** termios baud  
- AC: `configureSerial` applies 8N1 + requested baud via Darwin termios (`cfsetspeed` / `tcsetattr`). Baud is not discarded.  
- Out of scope: DTR/RTS, IOKit matching rewrite.  
- Verify: `ShopPilotVerify1401b` — if hardware-less, extract `SerialTermiosSettings.make(baud:)` and assert `B115200` mapping; integration comment that FileHandle path calls it.

**SPK-1401c** Newline + G90  
- AC: `sendCommand` appends `\n` if missing. Jog sends `G91 G0 …` then `G90` (or a documented modal restore).  
- Out of scope: soft-limit envelope.  
- Verify: `ShopPilotVerify1401c` recording transport writes.

**SPK-1401d** ALARM + timeout  
- AC: `waitForOk` throws on `ALARM:` / `error:` / `error N`. Times out (e.g. 5s) instead of hanging.  
- Out of scope: char-count streaming.  
- Verify: `ShopPilotVerify0417` / streamer tests + `ShopPilotVerify1401d` injecting alarm bytes.

**SPK-1401e** Single realtime writer  
- AC: `MachineController.hold/reset` call **either** session **or** streamer, not both. One `!` / one `0x18` per user action.  
- Verify: `ShopPilotVerify1401e` write log count.

**SPK-1401f** Status `?`  
- AC: polling loop writes `?` on an interval while connected.  
- Verify: `ShopPilotVerify1401f` fake transport sees `?`.

### Track C

**SPK-1402a** Wire Autosaver  
- AC: `AppSession` starts `Autosaver` (existing 5-min interval); dirty jobs write recovery; launch can offer recover if a file exists (`AutosaveRecovery`).  
- Out of scope: iCloud. Deps: not parallel with 1400a.  
- Verify: `ShopPilotVerify1312` if it exists and actually covers session start; else `ShopPilotVerify1402a`.

**SPK-1402b** Corrupt sheets  
- AC: `DocumentLoader` does not skip corrupt sheet JSON silently; open fails or returns a user-visible warning list.  
- Verify: `ShopPilotVerify1402b` fixture with one bad sheet file.

**SPK-1402c** Metal honesty  
- AC: `checkMetalAvailability()` returns a real `MTLCreateSystemDefaultDevice() != nil` **or** is removed from UI claims. Preview copy does not say Metal if it is SwiftUI.  
- Verify: `ShopPilotVerify1402c` trivial.

---

## Prompts — Wave 0

Paste **one prompt per worker**. Replace `WORKTREE` with the worktree path. Serial cards (1401b/d) omit the UI briefing. UI cards (1400a, and 1400c in Wave 1) include the briefing block below.

### UI card preamble (append after the AC on every SPK-1400* prompt)

```
UI doctrine (do not violate):
- Mac creative app, not CLI. Keep the 6-stage rail, progressive disclosure, Hold/Resume/Reset, no auto-run, SF Symbols.
- Canvas-dominant. Palettes + inspector. Coach + ⌘K stay.
- One stage/palette this card. Preserve bindings and safety chrome.
- HIG: toolbar = frequent actions; inspector = params (Form); overflow + ⌘K = the rest.
- Icon-first palettes where a create-tool exists. First-run = SampleProjectsStore recipes, not a new catalog.
- Do NOT: NavigationSplitView rewrite, stage rainbow colors, extra floating palettes, “redesign the whole app”, serial/termios/streamer work.
- Unpushed Design tool palette already exists — do not redo Design tools; Cut/Setup are the remaining stacks.
```

### Prompt: SPK-1401b (coder)

```
You are building ShopPilot at WORKTREE (worktree only; never edit ~/Desktop/ShopPilot/Sources).
Read AGENTS.md safety. Parent: SPK-1401. Card: SPK-1401b.

AC:
- Engine: RealSerialTransport.configureSerial applies Darwin termios 8N1 at the requested baud (do not discard baudRate).
- Persist: N/A
- Verify: ShopPilotVerify1401b

Out of scope: MachineConnection UI, GCodeStreamer, jog G90, IOKit matching rewrite, DTR/RTS.

Do:
- Sources/ShopPilotSerial/RealSerialTransport.swift
- Extract baud→speed_t mapping if needed so the CLT can test without a port
- Register executableTarget ShopPilotVerify1401b in Package.swift (dependencies: ShopPilotSerial and/or ShopPilotCore)
- All swift via ./scripts/swift_locked.sh or ./scripts/verify_locked.sh
- Never rm -rf .build
- If lock is waiting, heartbeat and wait — do not start a second swift

Verify: ./scripts/verify_locked.sh ShopPilotVerify1401b
Print PASS line: 1401b: PASS — termios baud applied
Then kanban_complete. Do not expand scope.
```

### Prompt: SPK-1401d (coder)

```
You are building ShopPilot at WORKTREE (worktree only).
Read AGENTS.md §2. Parent: SPK-1401. Card: SPK-1401d.

AC:
- Engine: GCodeStreamer waitForOk treats ALARM: and error: / error N as failure (throw). Wait has a timeout (default 5s) so a silent controller cannot hang forever.
- UI: N/A this slice
- Verify: ShopPilotVerify1401d

Out of scope: termios, jog newlines, Hold double-send, char-count streaming.

Do:
- Sources/ShopPilotCore/GCodeStreamer.swift only (plus new verify target)
- Keep ok-wait mode; do not switch to character-count
- Register ShopPilotVerify1401d in Package.swift (ShopPilotCore)
- Swift only via swift_locked / verify_locked; never rm -rf .build; worktree only

Verify: ./scripts/verify_locked.sh ShopPilotVerify1401d
Print: 1401d: PASS — alarm/error/timeout
kanban_complete. No scope creep.
```

### Prompt: SPK-1400a (coder)

```
You are building ShopPilot at WORKTREE (worktree only).
Read docs/planning/UI_REEVALUATION_AND_MARKET_RESEARCH.md §4 P0 items 1–2.
Parent: SPK-1400. Card: SPK-1400a.

AC:
- UI: WelcomeSheetView is a Start Making sheet: headline, 4 sample cards from SampleProjectsStore.samples (name + tagline). Click → session.applyPackagePayload(payload) (already on AppSession) then onDone().
- UI: "Open…" presents the real package open path (FileOperations / NSOpenPanel used by the File menu), not selectedStage = .design.
- UI: "Import…" presents ImportHubView (or the same import flow as Design), not a stage switch.
- Engine: add AppSession.loadSampleProject(id: UUID) -> Bool wrapping SampleProjectsStore.payload + applyPackagePayload. Keep applyPackagePayload landing on Design.

Out of scope: Setup Advanced disclosure, Cut toolbar, StageEnum copy, Autosaver, serial/termios/streamer.

UI doctrine (do not violate):
- Mac creative app, not CLI. Keep the 6-stage rail, progressive disclosure, Hold/Resume/Reset, no auto-run, SF Symbols.
- Canvas-dominant. Palettes + inspector. Coach + ⌘K stay.
- One stage/palette this card. Preserve bindings and safety chrome.
- HIG: toolbar = frequent actions; inspector = params (Form); overflow + ⌘K = the rest.
- Icon-first palettes where a create-tool exists. First-run = SampleProjectsStore recipes, not a new catalog.
- Do NOT: NavigationSplitView rewrite, stage rainbow colors, extra floating palettes, “redesign the whole app”, serial/termios/streamer work.
- Unpushed Design tool palette already exists — do not redo Design tools.

Do:
- Sources/ShopPilot/WelcomeSheetView.swift
- Sources/ShopPilot/AppSession.swift (loadSampleProject only — do not refactor the god object)
- Sources/ShopPilot/FileOperations.swift if that is where open lives
- Add ShopPilotVerify1400a: Core-side catalog — every SampleProjectsStore.samples id has a payload (can call through a thin WelcomeStartCatalog in Core that the view uses so the CLT does not need the app target)
- WelcomeSheetView MUST use that catalog / SampleProjectsStore — do not hardcode a second list of names
- Swift via lock; never rm -rf .build; worktree only

Verify: ./scripts/verify_locked.sh ShopPilotVerify1313 && ./scripts/verify_locked.sh ShopPilotVerify1400a
Print: 1400a: PASS — welcome samples + real open/import
kanban_complete.
```

### Prompt: SPK-1400c (coder or spark)

```
You are building ShopPilot at WORKTREE (worktree only).
Parent: SPK-1400. Card: SPK-1400c.

AC:
- Add Sources/ShopPilotCore/FriendlyCopy.swift with stage intents:
  setup: "Set up your board"
  design: "Draw it, or bring in a file"
  model: "Add 3D relief if you need it"
  cut: "Plan the cuts"
  preview: "See the cut before you run it"
  machine: "Connect, zero, and run"
- Stage.intent in Sources/ShopPilot/StageEnum.swift returns FriendlyCopy.intent(for:)
- Do not edit ContentView.swift (Untitled Project is 1400d / chrome follow-up). Do not rewrite CoachPanelView.

Out of scope: Welcome samples, Setup collapse, Cut recipes, serial, ContentView.

UI doctrine (do not violate):
- Mac creative app, not CLI. Keep the 6-stage rail, progressive disclosure, Hold/Resume/Reset, no auto-run, SF Symbols.
- Canvas-dominant. Palettes + inspector. Coach + ⌘K stay.
- One stage/palette this card. Preserve bindings and safety chrome.
- Do NOT: NavigationSplitView rewrite, stage rainbow colors, extra floating palettes, serial work.

Verify: ./scripts/verify_locked.sh ShopPilotVerify1400c
  (assert the six FriendlyCopy strings)
Print: 1400c: PASS — friendly stage copy
Swift lock; no .build wipe; worktree only. kanban_complete.
```

### Prompt: SPK-1400b (coder) — Wave 2, ContentView lock

```
You are building ShopPilot at WORKTREE (worktree only).
Parent: SPK-1400. Card: SPK-1400b.
Read docs/planning/FRIENDLINESS_AND_SERIAL_PATH.md Agent briefing.

AC:
- SetupStageView: NewJob + Material first. Sheets, Double-sided, Rotary, Document Variables, Driven Dimensions, Golden Jobs inside one DisclosureGroup("Advanced").
- Do not remove those panels — hide them under Advanced.

Out of scope: Welcome, Cut toolbar, serial, NavigationSplitView, new floating palettes.

UI doctrine: Mac creative app; 6-stage rail; Hold/Resume/Reset; no auto-run; SF Symbols; one stage this card; inspector stays; no rainbow chrome.

Do: Sources/ShopPilot/ContentView.swift SetupStageView only.
Verify: scripts/verify_1400b_setup.py (DisclosureGroup("Advanced") present; RotarySetupView after it) OR ShopPilotVerify1400b.
Print: 1400b: PASS — setup advanced disclosure
Swift lock; no .build wipe; worktree only. kanban_complete.
```

### Prompt: SPK-1400e (coder) — Wave 2, after 1400b (same ContentView)

```
You are building ShopPilot at WORKTREE (worktree only).
Parent: SPK-1400. Card: SPK-1400e.
Read docs/planning/FRIENDLINESS_AND_SERIAL_PATH.md Agent briefing.

AC:
- Cut default row: Cut out (profile), Pocket, Engrave (V-carve), More (remaining strategies + Fixture G-code, Post Studio, Enqueue, Job Sheet).
- Follow Source + Recalculate Dirty stay on the default row.
- Do not delete engines. Icon-first / recipe labels, not a 20-item button wall.

Out of scope: Cut left-column collapse (1400h), serial, NavigationSplitView.

UI doctrine: toolbar = frequent actions; More + ⌘K = the rest; no extra floating palettes.

Do: Sources/ShopPilot/ContentView.swift CutStageView toolbar only.
Verify: python/script: three recipe labels exist; "Photo V-Carve" is not a top-level Button in the first Cut HStack.
Print: 1400e: PASS — cut recipes
Swift lock; no .build wipe; worktree only. kanban_complete.
```

### Prompt: SPK-1401a (coder) — Wave 1, after 1401b

```
You are building ShopPilot at WORKTREE (worktree only).
Parent: SPK-1401. Card: SPK-1401a.

AC:
- transport.open(config:) receives the UI port and baud (ShopPilotCore.SerialConfig).
- TransportFactory serial builder uses the config argument, not _.
- MachineSession.connect passes the same config.

Out of scope: termios internals (1401b), jog G90, waitForOk, UI friendliness.

Do: MachineConnection.swift, App.swift, MachineSession.swift. Fake transport in ShopPilotVerify1401a records last SerialConfig.
Verify: ./scripts/verify_locked.sh ShopPilotVerify1401a
Print: 1401a: PASS — config reaches open
Swift lock; no .build wipe; worktree only. kanban_complete.
```

---

## Orchestrator notes

1. Create worktrees from `main` (or current branch) **after** committing the unpushed Design palette if you want agents to build on it. If Design menus are still dirty, **commit or stash** before Wave 0 or 1400a will conflict with `ContentView.swift`.
2. 1400a touches `AppSession.swift` (3-line `designTool` already dirty). Land local Design palette first, then branch Wave 0.
3. Do not dispatch 1400b/d/e/h until 1400a’s ContentView conflict risk is gone — 1400a should avoid ContentView if possible (Welcome is its own file). **Welcome is not ContentView** — 1400b can theoretically parallel 1400a. Still avoid two ContentView editors.
4. Human `[!]`: live air-cut (SPK-0419) still human. Agents must not claim live serial “done” without 1401a–f `[x]`.
5. Parents stay `[ ]` until children cover DoD.

---

## Out of this path

- App Store / notarization  
- Easy vs Expert SKU  
- Fusion ribbon  
- Full AppSession split  
- Char-count streaming  
- Claiming Metal preview as shipped  

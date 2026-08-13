# UI agent drive (native ShopPilot.app)

Companion to [`UI_ACCEPTANCE_DRIVER.md`](./UI_ACCEPTANCE_DRIVER.md). This file is the **how**: how Hermes or a Cursor agent actually clicks the SwiftUI app on a CLT Mac **without Xcode / XCUITest**, simulator only.

G1/G2 vision scripts stay in `UI_ACCEPTANCE_DRIVER.md`. Numeric truth stays in `ShopPilotVerify*` CLTs. This doc is the local AX harness plan.

---

## Honest constraint

“Agents can’t click SwiftUI” is **half-true**.

- SwiftUI is **not** a web DOM. There is no Playwright for `ShopPilot.app`.
- The app **is** an AppKit window with an Accessibility tree. Buttons with `Label("Hold")` / `.accessibilityLabel(...)` show up as AX titles/descriptions. Hermes already used this (2026-08-04 report): **AXPress works**; System Events `click at` often fails with `-25211` unless Accessibility + (sometimes) Input Monitoring is granted to the **driving process**.
- SPM `ShopPilot` is an **`executableTarget`**. `ShopPilotTests` is Core/Serial/Geometry — **not** a UI-test host. No XCUITest target. CLT Macs often have no `Xcode.app`.
- Cursor **cloud / Try Live** is a Linux/browser computer, not this user’s Aqua session. It cannot launch `.build/debug/ShopPilot`.
- Headless CLTs (`ShopPilotVerify0600/0601/1104*`) already prove connect → load (zero bytes) → preflight → stream → Hold/Resume. They do **not** prove chrome layout or that the Welcome sample is clickable.

So: agents **can** drive the native app **on the owner’s Mac** via Accessibility, if TCC is granted to the process that runs `scripts/ax_act.swift`. They **cannot** do it from a cloud VM or from a Hermes job that only has a sandbox without GUI/TCC.

---

## Ranked options (this repo)

| | Option | Hermes local | Cursor local | First 45–90m card |
| --- | --- | --- | --- | --- |
| **A (primary)** | AX: `scripts/ax_act.swift` + `capture_window.swift` (already in tree). Press by title/description. | Yes, if Terminal/Hermes is in Accessibility | Yes, if **Cursor.app** is in Accessibility | Wrap a **named smoke walk** (below) around existing tools |
| **E (backup)** | Expand Core CLTs (already the truth path) | Yes | Yes | Not visual; keep pairing with A |
| D | Screenshot + vision + click-by-click | Only with computer-use + Screen Recording | Local Cursor computer-use / user pastes shots | Fragile; use when AXPress misses a control |
| B | XCUITest | Usually **no** (`xcodebuild` + app host) | Same | Skip until Xcode.app is a given |
| C | Cursor cloud computer-use | N/A | **No** for native `.app` | Skip |
| F | Preview / ViewInspector | No live window | No | Skip for SPK-0623 chrome |

**Primary: A. Backup: E** (re-run `verify_locked.sh ShopPilotVerify0600` / `0601` / `1104d` whenever the AX walk is BLOCKED). Do not invent XCUITest on CLT.

Existing pieces (do not rewrite):

- `scripts/ax_act.swift` — `dump | press <substring> | setvalue | presspos`
- `scripts/ax_dump.applescript` / `ax_click.applescript` / `ax_press.applescript`
- `scripts/capture_window.swift` — `screencapture -l` by pid
- Past walk: `docs/planning/UI_ACCEPTANCE_REPORT_20260804.md` (AXPress; CGEvent clicks denied)

---

## Human once (TCC)

On the Mac that will run the driver:

1. **System Settings → Privacy & Security → Accessibility** — enable the process that executes the script:
   - Terminal and/or iTerm (Hermes `osascript` / `swift scripts/ax_act.swift`)
   - **Cursor** if a Cursor agent runs the same commands
2. **Screen Recording** — same apps, if you want `capture_window.swift` / vision asserts.
3. Relaunch those apps after toggling.
4. Optional: Input Monitoring — only if you later need `cliclick` / CGEvent. Prefer AXPress so you can skip this.

If `ax_act.swift <pid> dump` prints `no windows / AX denied`, TCC is the blocker — file BLOCKED, do not fake PASS.

---

## First-run walk (AX names from current code)

Launch: `./scripts/swift_locked.sh build --product ShopPilot` then run `.build/debug/ShopPilot` (or `dist/ShopPilot.app` if packaged). Simulator only. Never pick a real serial port.

**Welcome** (`WelcomeSheetView`, first launch / Help → welcome). Sample AX titles = store names:

| Click (title / description contains) | Source |
| --- | --- |
| `Sign — V-Carve Greeting` | `SampleProjectsStore` (preferred sample) |
| or Design empty-state `Try a sample` | `ContentView` — loads **first** sample (same Sign) |
| `Get Started` | dismiss without sample |
| `Start a New Job` | Setup, empty job |

After sample load, stage is Design.

| Step | Press / assert | AX substring |
| --- | --- | --- |
| 1 Design | Rail | `Design` (`StageRailView` accessibilityLabel = stage title) |
| 2 Cut | Rail | `Cut` |
| 3 Profile | Button | `Cut out` |
| 4 Preview | Rail | `Preview` |
| 5 Optional sim | Button | `Simulate` |
| 6 Handoff | Button | `Continue to Machine` **or** Cut-stage `Send to Machine Stage` |
| 7 Transport | Picker value | `Simulator` (not a USB path) |
| 8 Connect | Button | `Connect` (help: “Open the port — no motion…”) |
| 9 Safety chrome | Visible | `Hold. Pause machine motion` **or** title `Hold`; `Reset. Stop` |
| 10 No auto-run | Dump console / idle | Must **not** be streaming until Run |
| 11 Preflight | Button | `I've checked all of these` / `Confirm pre-flight checklist` |
| 12 Start | Button | `Run Job` / `Run job. Start cutting` |
| 13 Hold | Button | `Hold` / `Hold. Pause machine motion now` |
| 14 Resume | Button | `Resume` / `Resume. Continue machine motion` |

Shortcuts if AXPress on rail is flaky: ⌘2 Design, ⌘4 Cut, ⌘5 Preview, ⌘6 Machine (`StageEnum.shortcutCharacter`). Safety: ⌘⌥H Hold, ⌘⌥R Resume, ⌘⌥X Reset.

**Out of first smoke:** G1-C dirty export (needs pointer select — historically TCC-blocked), G1-D open-vector pick, live serial, notarize.

Pair after (or instead if AX denied): `./scripts/verify_locked.sh ShopPilotVerify0601` and Hold CLT `ShopPilotVerify1104d` / `1401e`.

---

## Thin card (what to build — not computer-use)

See **SPK-0623a** on `MASTER_KANBAN.md`: one bash (or python) wrapper that launches the app, `ax_act dump`, `press` the table above, `capture_window` into `/tmp/shoppilot-ui-drive-*`, exits 0 on PASS / 3 on NOT FOUND / 4 on AX denied. Do **not** mark SPK-0623 from that script.

Smoke: `scripts/ui_drive_smoke.sh` (G1-style Hold/Resume only).
Full catalog: `scripts/ui_drive_full.sh` (**SPK-0623b**) — see **Full walk** below.

---

## Human TCC reminder (every GUI run)

The full walk **must** run in a **local Aqua session** (owner’s Mac, Hermes/Terminal/Cursor with GUI). Cloud agents cannot do this.

1. **System Settings → Privacy & Security → Accessibility** — enable the **same process** that will execute `scripts/ui_drive_full.sh` (Terminal, iTerm, Hermes host, or **Cursor.app**).
2. Relaunch that app after toggling. A grant that was added while the process was already running is ignored.
3. **Screen Recording** — same apps, for `/tmp/shoppilot-ui-drive-full-*.png`. Missing Screen Recording skips shots; it is **not** a PASS/FAIL substitute.
4. If `ax_act.swift <pid> dump` prints `no windows / AX denied` → exit **4**. Do not fake PASS. Do not “force-quit and call it done.”
5. Simulator only. Never pick a USB serial port.

---

## Surface inventory (dismiss paths) — 2026-08-13

Source: `Sources/ShopPilot`. Expected dismiss is what a human should use. **Suspect** = easy to trap the app / need force-quit.

| Surface | Kind | Expected dismiss | Notes / suspects |
| --- | --- | --- | --- |
| Welcome `WelcomeSheetView` | `.sheet` | Sample card **or** `Get Started` | No Cancel; sample/`Get Started` is enough |
| Recovery `RecoveryOfferView` | `.sheet` | `Discard` / `Recover`; Esc → Discard | OK |
| Safety `SafetyDisclaimerView` | `.sheet` | **`I Understand` only** | **SUSPECT:** `.interactiveDismissDisabled(true)` — no Cancel, no Esc, no red-light close on the sheet. Help → Safety Notice can trap unless AX finds `I Understand`. |
| Import hub `ImportHubView` | `.sheet` | `Cancel` (also ⌘.) | OK — explicit Cancel |
| Post Studio `PostStudioView` | `.sheet` | `Done`; delete alert `Cancel` | OK |
| Command palette overlay | overlay not a sheet | Esc (hidden AX button) / click dimmer | **SUSPECT for AX:** Esc control is `accessibilityHidden`. No Cancel/Done. Full walk does **not** open palette first. |
| Preferences `PreferencesView` | `Settings { }` scene | **red traffic light / ⌘W / Esc** — **no Cancel/Done in the form** | **SUSPECT (the bug class):** Settings window with no in-content dismiss. Walk **must** close it. Fail **5** if AX has no close/Cancel. |
| File New Job | menu | n/a (no dialog) | `App.swift` CommandGroup |
| File Open Job… | menu → `NSOpenPanel` | panel **Cancel** | Must dismiss; never hang on the picker |
| File Save / Save As… | menu → save panel | panel **Cancel** | Same |
| File Export G-code… | menu → save panel | **Cancel** | Out of first full walk (easy to confuse with Cut Save) |
| Help Safety Notice | menu | same as Safety sheet | See suspect above |
| Help README / Lean CNC Scope | menu | opens files in another app | Skip / don’t wait |
| Design tool alerts (Offset, Dogbone, Fillet, Extend, Array, Circular, Nest, Tile, Keyhole, Set Size, Add Text, Linear/Circular Array Copy) | `.alert` | `Cancel` | All have Cancel |
| Export block / toolpath preflight | `.alert` | `Cancel` | OK |
| Sheet list Remove / editor | alert + sheet | `Cancel` | Setup → Advanced |
| Recipe picker | sheet + confirm alert | `Cancel` | Setup New Job |
| Doc vars add/delete | sheet + alert | `Cancel` | Advanced |
| Keep-out editor | sheet | `Cancel` | Cut → More |
| Tool browser cut-data | sheet | `Cancel` | |
| Model: Split Relief alert; STL wizard; Composite render; Laser toolpath; Combine teacher | alert/sheets | Cancel / Done | Laser sheet **out of lean walk** (do not expand laser) |
| Inspector `InspectorShell` | sidebar | not a modal | No dismiss required |
| Stage rail | chrome | n/a | Setup / Design / Model / Cut / Preview / Machine |

---

## Full walk (SPK-0623b)

```bash
# No GUI — prints the catalog, exit 0
scripts/ui_drive_full.sh --self-check

# Live Aqua + Accessibility TCC (do not compile inside the walk)
# If the binary is missing:
#   ./scripts/swift_locked.sh build --product ShopPilot
scripts/ui_drive_full.sh
```

Helpers: **only** `scripts/ax_act.swift` + `scripts/capture_window.swift`. `ax_act` dump/press also walks the **menu bar** and window **close** buttons so File/Help/Preferences and Settings dismiss work.

| | |
| --- | --- |
| Screenshots | `/tmp/shoppilot-ui-drive-full-*.png` |
| AX dumps | `/tmp/shoppilot-ui-drive-full-dumps/` |
| Exit 0 | PASS |
| Exit 2 | binary missing (print `swift_locked.sh build --product ShopPilot`; do not compile while the lock is messy) |
| Exit 3 | control NOT FOUND (catalog continues; worst code wins) |
| Exit 4 | AX denied — **STOP** |
| Exit 5 | **DIALOG STUCK** — no Cancel/Done/Close/`I Understand`/window close in AX. Dump path printed. **Force-quit is not success.** |

Walk order (matches `--self-check`): Welcome sample → File New → File Open (**Cancel the panel**) → File Save (**Cancel**) → Setup Advanced open/close → Design tools + Import hub Cancel → Cut out / Pocket / Engrave / More → Preview → Machine Simulator Connect → **Preferences open then CLOSE** → Help Safety Notice dismiss → preflight → Run → Hold → Resume.

On each fail: log, keep going unless exit 4. File thin `SPK-UI-BUG-*` cards (dialog name + missing dismiss). **Never mark SPK-0623 `[x]`.**

---

## Hermes paste prompt (SPK-0623b live run)

```text
You are a local Hermes/coder agent on the owner's Mac (Aqua GUI). Accessibility TCC is granted to THIS process (Terminal/Hermes). ShopPilot is at ~/Desktop/ShopPilot.

## Mission
RUN the comprehensive native-app UI catalog — not --self-check only. Catch "no way to close a dialog / force-quit" bugs. Simulator only. No CNC. No laser expansion. Do NOT mark SPK-0623 [x].

## Read
- AGENTS.md safety (no auto-run, no live serial)
- docs/planning/UI_AGENT_DRIVE.md (Full walk + inventory)
- MASTER_KANBAN SPK-0623b (parent 0623 stays [ ] human)

## Run
cd ~/Desktop/ShopPilot
# If binary missing, ONE compile then walk (do not compile inside the walk if swift lock is held):
#   ./scripts/swift_locked.sh build --product ShopPilot
scripts/ui_drive_full.sh
# Tools: ONLY scripts/ax_act.swift + scripts/capture_window.swift. No cliclick. No osascript click-at. Never rm -rf .build. Never pick Serial / USB.

## On each failure
- Exit 4 AX denied → STOP. Print TCC hint. Do not fake PASS.
- Exit 5 DIALOG STUCK or a sheet with no Cancel/Done/Close/Esc-equivalent → create a thin MASTER_KANBAN card SPK-UI-BUG-* with: dialog/sheet name, missing dismiss control, dump path under /tmp/shoppilot-ui-drive-full-dumps/, screenshot if any. Force-quit is NOT success.
- Exit 3 NOT FOUND → same: thin card with the missing AX substring; keep going.
- Timebox: continue through the catalog after 3/5 (script already continues). Stop only on AX denied or catalog complete.
- Work log on SPK-0623b. Leave SPK-0623 [ ].

## STOP
AX denied, or the press plan in ui_drive_full.sh --self-check has been executed.
```


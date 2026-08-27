# ShopPilot

**Native macOS CNC suite** — design vector art, generate 2.5D toolpaths, simulate the cut, and run your machine. All on the Mac you already own.

> 🛑 **Safety first:** ShopPilot is a CAM + machine-control app. The Preview heightfield and the built-in **simulator** are rehearsal tools — they complement but do **not** replace a hardware e-stop. Simulate, then air-cut, then cut. Keep a physical e-stop within reach.

**New here?** [**Quickstart (~15 min)**](docs/planning/QUICKSTART.md) — Welcome sample → Design → Cut → Preview → Machine Simulator. No USB required.

[![Release](https://img.shields.io/badge/release-0.07-brightgreen)](#download)
[![macOS](https://img.shields.io/badge/macOS-14+-black?logo=apple&logoColor=white)](https://developer.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-blue)](#download)
[![License](https://img.shields.io/badge/license-proprietary-lightgrey)](LICENSE)

---

## Screenshots

Gallery: [`docs/screenshots/`](docs/screenshots/README.md). Shots below match the **0.07** UI. Preview is a SwiftUI **2.5D filled heightfield + playhead**. Laser module is not a current product.

| Welcome | Design | Cut recipes |
| --- | --- | --- |
| ![Welcome / Start Making samples](docs/screenshots/welcome.png) | ![Design canvas](docs/screenshots/design.png) | ![Cut stage](docs/screenshots/cut.png) |

| Preview (pocket + stepover) | Preview (playhead) | Preview (3D relief) |
| --- | --- | --- |
| ![Filled 2D pocket heightfield](docs/screenshots/2d-pocket-stepover.png) | ![Playhead mid-sim](docs/screenshots/2d-playhead.png) | ![Rough 3D plaque heightfield](docs/screenshots/3d-relief-sim.png) |

| Machine (simulator) |
| --- |
| ![Machine + Simulator; Hold and Reset](docs/screenshots/machine-sim.png) |

Older numbered stills (`01-setup.png` … `06-preview.png`) remain in the same folder as aliases.

---

## Why ShopPilot?

- **Native.** SwiftUI + CoreGraphics on Apple Silicon and Intel — a single universal binary.
- **A 2.5D CAM suite.** Vectors, booleans, layers, **Profile / Pocket / Drill / V-Carve / Trochoid Slot**, and **3D rough/finish** from an STL or plaque heightfield. Model orbit is a thin 2.5D relief view.
- **Welcome samples + stage rail + Cut recipes.** First launch: bundled sign, box, keychain, plaque. Six stages: **Setup → Design → Model → Cut → Preview → Machine**. Cut uses recipe buttons (Cut out / Pocket / Engrave + More).
- **First-hour CAM chrome.** Grid snap, marquee select, canvas XY DRO, sheet origin (corner/center), inspector **F / S / Z**, tabs/leads on the Design overlay, large **Machine DRO**, Model **Orbit**.
- **Machine control built in.** Jog, work zero, touch-off probe, feed override, G54–G59, spindle, serial to GRBL/FluidNC, plus **frame job** and **click-to-jog**. **The bar is the simulator** (Hold / Resume / Reset always visible); live serial is available too.
- **Safety by design.** Preflight before Run, no auto-run on load, dirty-toolpath export blocking. Software complements but does not replace a hardware e-stop.

> **Scope:** personal use only, never for sale. A focused 2.5D relief CAM tool, not a 3D parametric CAD suite.

---

## Features

### Job & setup
- **Job setup** — single- or double-sided stock with sheet presets, custom material, mm/inch, document variables, driven dimensions.
- **Recipes** — Signage, Decorative Panel, Portrait Relief (pre-build design + toolpath tree).
- **Experience mode** — Beginner / Advanced switch (Preferences or Welcome); Beginner hides pro surfaces without deleting them.
- **Sample projects** — Welcome / Start Making: sign, box, keychain, plaque (re-open Welcome after first run).
- **Documents** — `.shoppilot` packages, 5-minute autosave + crash recovery, undo/redo.
- **Job sheets** — A4 HTML → PDF from Cut.

### Design (2D)
- **Create** — rectangle, circle, line, polyline, text (glyphs → curves, text on curve, 3D text relief).
- **Edit** — select/drag, **marquee**, multi-select, node editing, measure, dimension handles; **grid snap**; live **XY DRO**.
- **Origin** — sheet datum corner or center (job-level persist).
- **Operations** — Offset, Weld, Subtract, Intersect, Join, Close, Trim, Fillet, Extend, dogbone, vector boundary, Array/Circular copy, Keyhole, **Nest** (sheet-goods packing with rotation + spacing).
- **Layers** — hide/lock, reorder; multi-sheet with duplication and toolpath transfer.
- **Import / export** — SVG, DXF, EPS, PDF, AI, DWG, WebP, bitmap trace, STL; design PDF export.

### Model & 3D (lean spine)
- STL → relief and bitmap → relief heightfields; 3D text; components / combine / mirror / sculpt strokes.
- **Image-to-Relief** (auto-levels, smoothing, detail boost) and **Photo Lithophane** (thickness or grayscale mode) from the Model/Photo starters.
- **Rough 3D / Finish 3D / rest machining** from the heightfield.
- **Orbit** — thin 2.5D relief view.

### Toolpaths (CAM)
- **Profile** — in/out/on, climb/conventional, passes, **tabs**, ramping, **leads**, corner sharpen, ordering, allowance. Tabs/leads draw on the Design overlay.
- **Pocket** — offset/raster, multi-tool clearance, allowance, ramping.
- **Drill** — peck cycles, dwell, plunge feeds.
- **V-Carve** — depth shading, V-bit presets, flat-depth, clearance-tool, inlay recipes.
- **Trochoid Slot** — constant-engagement slotting loops for closed corridors (Cut → More; Advanced mode), ramp entry, too-narrow gate.
- **Inlay** — V-walls-then-floor cut sequence, clearance-tool handling, crisp-letters medial cell preset.
- **Inspector** — selected op **feed / spindle / Z** in the inspector shell.
- **Tool database** — classes, strategy defaults, manufacturer catalogs (Amana, Whiteside).
- **Tree & safety** — status dots, **async generate/recalc** (Cut out does not freeze the UI), keep-out zones, time estimates, templates, dirty-export blocking.

### Cut quality (0.07)
- **Drop-cutter 3D finish** — ball-nose compensation; finish stepover defaults to 8–12% of tool Ø for a clean surface finish.
- **Rest finish** — only the cusps and narrow valleys a previous larger ball couldn't reach get finish-machined.
- **Scallop-leftover preview** — honest cusp-height tint against the 0.02 mm shop band.
- **Photo V-Carve geometry** — groove width derives from V-angle + tip Ø + depth; 45° default raster, luminance invert, two-pass rough + finish.
- **V-bit flat tip** — wide-valley depth accounts for real (non-sharp) V-bit tips.

### Preview
- Full-tree **wireframe** plus sheet-aware **filled heightfield** (bit-radius stamp, cancellable). **Playhead / Play** over sim time. 2.5D raster preview.

### Machine control
- **Transports** — **simulator first**; real serial (GRBL/FluidNC) with port/baud pickers.
- **Operation** — jog, home, work zero, G38.2 touch-off, feed override, spindle, G54–G59, stream G-code, **frame job**, **click-to-jog**, Hold / Resume / Reset, raw TX/RX console, large **Machine DRO**.
- **Safety** — preflight gates Start; zero bytes on load (no auto-run); disconnect stops the stream; Hold / Reset always visible while connected.

### Platform & UX
- **Stage rail** — Setup → Design → Model → Cut → Preview → Machine, ≤12 icons per stage.
- **Machine helpers** — **Frame job** (safe-Z G0 rectangle around job bounds) and **click-to-jog** on the canvas, both gated behind connected + Idle.
- **⌘K**, context menus, coach strip, editable shortcuts, GRBL-oriented post templates.

---

## Download

Grab the prebuilt app — no build required:

1. Download [`dist/ShopPilot-0.07-macOS.zip`](dist/ShopPilot-0.07-macOS.zip) (universal: Apple Silicon + Intel, ad-hoc signed) — or build with `scripts/package_app.sh`.
2. Unzip and drag **ShopPilot.app** into Applications.
3. First launch from another Mac: **right-click → Open** (Gatekeeper), or:
   ```bash
   xattr -dr com.apple.quarantine /Applications/ShopPilot.app
   ```

Previous releases: [`dist/`](dist/) — `0.01` … `0.07`, each a universal zip rebuilt from source.

*The zip is rebuilt from source with [`scripts/package_app.sh`](scripts/package_app.sh) — the unpacked `.app` is not committed. `CFBundleShortVersionString` is the `VERSION` you pass to that script.*

---

## Build from source

Requires **Xcode 15+** (macOS 14+ SDK).

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Prefer the lock when other terminals may compile
./scripts/swift_locked.sh build --product ShopPilot
./scripts/swift_locked.sh run ShopPilot

# Single CLT (repo test gate — CLT has no XCTest)
./scripts/verify_locked.sh ShopPilotVerify1201

# Phase Y cut-quality audit (params reach the G-code; no dead toggles)
./scripts/verify_locked.sh ShopPilotVerifyPhaseYAudit
bash scripts/sweep_phasey.sh          # whole cut-quality phase + byte-goldens
```

Release zip (match the committed 0.07 artifact):

```bash
VERSION=0.07 ZIP_NAME=ShopPilot-0.07-macOS.zip ./scripts/package_app.sh
# → dist/ShopPilot-0.07-macOS.zip (universal arm64 + x86_64, ad-hoc signed)
```

Do not run bare `swift build` / `swift test` as the default gate.

---

## First 15 minutes

**Start here:** [`docs/planning/QUICKSTART.md`](docs/planning/QUICKSTART.md) (numbered, screenshoted).

1. **Welcome / Setup** — Safety **I Understand**, then try a sample (sign, box, keychain, plaque) or a recipe.
2. **Design** — Rect / Circle / Line / Polyline, text, or import SVG / DXF / STL. Toggle **snap**; marquee-select; **Space** to pan; watch the **XY DRO**.
3. **Cut** — Cut out / Pocket / Engrave (or More). Wait for generate (async). Export stays blocked while dirty.
4. **Preview** — Simulate; use the **playhead**. Filled heightfield.
5. **Model** (optional) — relief + Rough/Finish 3D; **Orbit** for a 2.5D look-around.
6. **Machine** — **Simulator** → Connect → preflight → **you** press Run. Hold / Reset stay visible. Serial is optional.

Longer walkthrough: [`docs/planning/TUTORIAL_FIRST_CUT.md`](docs/planning/TUTORIAL_FIRST_CUT.md)

---

## Where to work

| Doc | Role |
| --- | --- |
| [`docs/planning/QUICKSTART.md`](docs/planning/QUICKSTART.md) | **Sit-down Quickstart** (~15 min, simulator) |
| [`docs/planning/TUTORIAL_FIRST_CUT.md`](docs/planning/TUTORIAL_FIRST_CUT.md) | End-user first-cut tutorial |
| [`docs/planning/CHANGELOG.md`](docs/planning/CHANGELOG.md) | Release history (0.01 → 0.07) |
| [`docs/planning/SAFETY.md`](docs/planning/SAFETY.md) | Safety policy |
| [`docs/planning/PACKAGING.md`](docs/planning/PACKAGING.md) | How to zip the `.app` (personal use) |
| [`docs/screenshots/README.md`](docs/screenshots/README.md) | Screenshot pack |

---

## Project status

**Current release:** personal-use **0.07** ([`dist/ShopPilot-0.07-macOS.zip`](dist/ShopPilot-0.07-macOS.zip)) — universal (arm64 + x86_64), ad-hoc signed. Lean bar: router CAM — design → toolpaths → 2.5D preview → **simulator** (live serial included).

**What's in 0.07** — on top of the 0.06 feature surface, this release lands the **cut-quality bar** (Phase Y): drop-cutter 3D finish with an 8–12% finish stepover, rest finish, scallop-leftover preview, V-bit flat-tip and groove geometry, two-pass photo/litho, and inlay V-walls-then-floor. It also ships the **Phase S parity wave** (image-to-relief, photo lithophane, sheet nesting, frame job + click-to-jog, Beginner/Advanced mode), **trochoidal slotting**, and a full **dogfood fix wave**. The Phase Y audit — 47 assertions against emitted G-code — guards the whole phase against dead parameters.

**Held / out of scope:** Preview remains a 2.5D heightfield (no full-3D viewport editing). Laser/LightBurn is **not** a current product. No App Store distribution. Personal-use only; never for sale.

Full per-release details: [`docs/planning/CHANGELOG.md`](docs/planning/CHANGELOG.md).

---

## Testing & verification

The repo tests through **headless CLT verification targets** (`ShopPilotVerify*`) that exercise engines, toolpath generation, the parser/streamer state machine, and regression goldens — driven by the scripts in [`scripts/`](scripts/). Run the suite:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/run_overnight_shakedown.sh   # → results/CLTS.md
```

**Finish definition = Engine + UI + Persist + Verify per feature.**

---

## Stack

SwiftUI · macOS 14+ · `ShopPilot` (app) · `ShopPilotCore` (engine) · `ShopPilotSerial` (transport) · `ShopPilotGeometry` (geometry) · `ShopPilotVerify*` CLT targets

## License

Proprietary — see `LICENSE`. **Personal use only; never for sale.** All code and documentation written from scratch; no third-party proprietary assets.

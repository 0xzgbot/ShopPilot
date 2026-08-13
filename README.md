# ShopPilot

**Native macOS CNC suite** — design vector art, generate 2.5D toolpaths, simulate the cut, and run your machine. All on the Mac you already own.

> 🛑 **Safety first:** ShopPilot is a toolpath generator, not a substitute for a hardware e-stop. Simulate everything before you cut.

[![macOS](https://img.shields.io/badge/macOS-14+-black?logo=apple&logoColor=white)](https://developer.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-blue)](#download)
[![License](https://img.shields.io/badge/license-proprietary-lightgrey)](LICENSE)

---

## Screenshots

| Setup & recipes | Design & vectors | Cut & toolpaths |
| --- | --- | --- |
| ![Setup](docs/screenshots/01-setup.png) | ![Design](docs/screenshots/02-design-signage.png) | ![Cut](docs/screenshots/03-cut.png) |

| Model & 3D | Machine & safety | Preview & sim |
| --- | --- | --- |
| ![Model](docs/screenshots/04-model.png) | ![Machine](docs/screenshots/05-machine.png) | ![Preview](docs/screenshots/06-preview.png) |

---

## Why ShopPilot?

- **Native, not a VM.** SwiftUI + CoreGraphics on Apple Silicon and Intel. No Parallels, no Boot Camp, no Windows license.
- **A real 2.5D CAM suite.** Vectors, boolean ops, layers, 17 toolpath strategies including V-Carve, 3D relief (rough/finish/rest), rotary wrap, laser, and inlay — with a sheet-aware simulation you trust before you cut.
- **Machine control built in.** Jog, set work zero, touch-off probe, feed override, work offsets (G54–G59), spindle control, and G-code streaming over serial to GRBL/FluidNC — or rehearse every job in the included simulator first.
- **Safety by design.** Preflight checklist before Run, always-visible **Hold / Resume / Reset**, dirty-toolpath export blocking, no auto-run on load.
- **Mac-native polish.** Custom app icon, brand accent, design-anchored canvas grid, material swatches, context menus, command palette, and a six-stage rail that walks a job from stock to chip.

---

## Features

### Job & setup
- **Job setup** — single- or double-sided stock with sheet presets, custom material, mm/inch units, document variables (expression-backed dimension fields), driven dimensions.
- **Recipes** — one-click Signage, Decorative Panel, and Portrait Relief jobs that pre-build the design and toolpath tree; JSON recipe format + plugin API.
- **Sample projects** — bundled sign, box, keychain, and plaque files on first launch.
- **Documents** — save/open `.shoppilot` packages (vectors + layers + toolpaths + params), 5-minute autosave with crash recovery, full undo/redo.
- **Job sheets** — print/export an A4 job sheet (HTML → PDF) from the Cut stage.

### Design (2D)
- **Create** — rectangle, circle, line, polyline, text (glyphs → curves, text on curve, **3D text relief**).
- **Edit** — select/drag, multi-select, node editing, measure tool, smart part selection with dimension handles.
- **Operations** — Offset, Weld, Subtract, Intersect, Join, Close, Trim, Fillet, Extend, **Dogbone corner relief**, **Vector boundary** (convex hull + offset), Array/Circular copy, Keyhole, Nest.
- **Layers** — per-layer hide & lock, reorder, layer-faithful save/open; multi-sheet documents with sheet duplication and toolpath transfer.
- **Import / export** — SVG, DXF, EPS, PDF, AI, DWG, WebP, bitmap trace, STL (ASCII/binary); **design PDF export**; import hardened against hostile input.

### Model & 3D (lean spine)
- **STL → relief** and **bitmap → relief** heightfield conversion.
- **3D text** — glyph outlines rasterized into a raised-letter heightfield.
- **Relief editing** — components, combine, mirror modes (X/Y/both), sculpt strokes.
- **3D toolpaths** — Rough 3D, Finish 3D, and **rest machining** (remaining-depth z-level passes) from the heightfield.

### Toolpaths (CAM)
- **Profile** — in/out/on cut, climb/conventional, pass depths, tabs, ramping, lead-in/out, corner sharpening, ordering & start-point strategies, allowance.
- **Pocket** — offset/raster fill, multi-tool clearance, allowance, ramping, pass control.
- **Drill** — peck cycles (fixed/relative retract, visualized), dwell, plunge feeds.
- **V-Carve** — per-vector depth shading, V-bit presets, flat-depth mode, clearance-tool pass, corner sharpen; **inlay** recipes (30/45/60/90°).
- **Specialty** — Quick Engrave, Drag Knife, Photo V-Carve, Texture, Fluting, Prism, Chamfer, Sketch Carve, **Thread milling**, rotary wrap/spiral, laser cut/fill/picture.
- **Tool database** — 13 tool classes, 17 strategy defaults, 3-part cut-data linkage (geometry/material/machine), **manufacturer catalogs** (Amana, Whiteside).
- **Tree & safety** — toolpath tree with status dots, per-op params, **async recalc** (no UI freeze), keep-out zones, **acceleration-aware time estimates**, toolpath templates, group-by-tool export, dirty-export blocking.

### Preview
- Full-tree wireframe overlay with hover highlighting, sheet-aware stock block, surface-color material simulation (wood/acrylic), peck-drill visualization, dirty-region resimulation — cancellable and non-blocking.

### Machine control
- **Transports** — built-in simulator plus real serial (GRBL/FluidNC) with **port/baud pickers**.
- **Operation** — jog, home, set work zero, **touch-off probing** (G38.2), **feed-rate override** (10–200%), **spindle on/off/RPM**, **work offsets G54–G59**, stream G-code, Hold / Resume / Reset realtime, raw TX/RX console.
- **Safety** — preflight checklist gates Start, zero bytes on load (no auto-run), disconnect stops the stream, E-stop / Reset always visible.

### Platform & UX
- **Stage rail** — Setup → Design → Model → Cut → Preview → Machine, CNC-meaningful icons, ≤12 icons per stage.
- **⌘K command palette**, context menus, stage-aware coach strip.
- **Editable keyboard shortcuts** (Preferences → Menu Shortcuts).
- **Post Studio** — user post templates with `$variable` blocks.
- **Plugin ABI** — sandboxed child-process plugins (bundled sample: dot-grid engrave).

> Scope (permanent): personal-use only, never for sale. **No 3D-view vector editing, no Fusion-style parametric modeling** — ShopPilot is a 2.5D CAM tool. Model-stage relief editing stays.

---

## Download

Grab the prebuilt app — no build required:

1. Download [`dist/ShopPilot-0.05-macOS.zip`](dist/ShopPilot-0.05-macOS.zip) (universal: Apple Silicon + Intel, ad-hoc signed) — or build it yourself with `scripts/package_app.sh`.
2. Unzip and drag **ShopPilot.app** into your Applications folder.
3. First launch from another Mac: **right-click → Open** (Gatekeeper), or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/ShopPilot.app
   ```

*The zip is rebuilt from source with [`scripts/package_app.sh`](scripts/package_app.sh) — the unpacked `.app` is deliberately not committed.*

---

## Build from source

Requires **Xcode 15+** (macOS 14+ SDK).

```bash
# Build (debug)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build

# Run
swift run ShopPilot

# Verify a single CLT target (the repo's test gate — see AGENTS.md)
./scripts/verify_locked.sh ShopPilotVerify1201
```

Release build (used by the packaging script):

```bash
swift build -c release --product ShopPilot
./scripts/package_app.sh          # → dist/ShopPilot-0.05-macOS.zip (universal)
```

> ⚠️ Use `./scripts/swift_locked.sh build` when multiple agents/terminals may build simultaneously — it serializes Swift invocations.

---

## First 15 minutes

1. **Setup** — pick a recipe (Signage, Decorative Panel, Portrait Relief) or a sample project, or set your own stock + material (swatch chips make it visual).
2. **Design** — draw with Rect / Circle / Line / Polyline, add text, or import **SVG / DXF / STL / EPS / PDF / AI / DWG**.
3. **Cut** — add Profile, Pocket, Drill, or V-Carve toolpaths. Edit art → toolpath goes **dirty** → recalculate before export (async — no freeze).
4. **Preview** — simulate the cut (wireframe / heightfield / combined) before you ever touch the machine.
5. **Machine** — connect to the **Simulator** first, pass the preflight checklist, run. Then do the same on real hardware via serial (pick your port + baud).

Full walkthrough: [`docs/planning/TUTORIAL_FIRST_CUT.md`](docs/planning/TUTORIAL_FIRST_CUT.md)

---

## Where to work

| Doc | Role |
| --- | --- |
| [`docs/planning/TUTORIAL_FIRST_CUT.md`](docs/planning/TUTORIAL_FIRST_CUT.md) | **End-user first-cut tutorial** |
| [`docs/planning/README_MAC_NATIVE.md`](docs/planning/README_MAC_NATIVE.md) | Product overview (planning archive) |
| [`MASTER_KANBAN.md`](MASTER_KANBAN.md) | **Only task board** — claim SPK cards here |
| [`docs/planning/CHANGELOG.md`](docs/planning/CHANGELOG.md) | Release history (0.01 → 0.05) |
| [`docs/planning/V2_SHIP_CHECKLIST.md`](docs/planning/V2_SHIP_CHECKLIST.md) | v2 feature-gate checklist (Phases I–N) |
| [`AGENTS.md`](AGENTS.md) | Agent protocol + safety rules |

---

## Status (honest)

**Current:** all Phases I–N feature cards are `[x]` on the board. The full regression sweep runs **175 verify targets** green — **175 PASS / 0 FAIL / 0 WARN** (last run 2026-08-11):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/run_overnight_shakedown.sh   # → results/CLTS.md
```

- Finish definition = **Engine + UI + Persist + Verify** per card (no stub estimators).
- Every code card `[x]` through Phase N; remaining open items are human-triggered (`[!]` SPK-0419 live air-cut) or permanently deferred (`[-]` — commercial-era cards, out of scope).
- A release **0.05** package (Phases O + P, live serial, persist honesty) is built on request via `scripts/package_app.sh`.

## Stack

SwiftUI · macOS 14+ · `ShopPilot` (app) · `ShopPilotCore` (engine) · `ShopPilotSerial` (transport) · `ShopPilotGeometry` (geometry) · 175 `ShopPilotVerify*` CLT targets

## License

Proprietary — see `LICENSE`. **Personal use only; never for sale.** All code and documentation written from scratch; no third-party proprietary assets are used in this project.

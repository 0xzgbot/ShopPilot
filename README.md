# ShopPilot

**Native macOS CNC suite** — design vector art, generate toolpaths, and run your machine. All on the Mac you already own.

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

- **Native, not a VM.** SwiftUI + Metal on Apple Silicon and Intel. No Parallels, no Boot Camp, no Windows license.
- **Aspire-class workflows.** Vectors, boolean ops, layers, Profile / Pocket / Drill / V-Carve toolpaths, 3D relief (Studio3D tier), heightfield preview.
- **Machine control built in.** Jog, set work zero, stream G-code over serial to GRBL/FluidNC — or rehearse every job in the included simulator first.
- **Safety by design.** Preflight checklist before Run, always-visible **Hold / Resume / Reset**, dirty-toolpath export blocking, no auto-run on load.

---

## Features

### Job & setup
- **Job setup** — single-sided stock with sheet presets (72 imperial/metric), custom material, mm/inch units, document variables.
- **Recipes** — one-click Signage, Decorative Panel, and Portrait Relief jobs that pre-build the design and toolpath tree.
- **Documents** — save/open `.shoppilot` packages (vectors + layers + toolpaths + params), autosave, full undo/redo.
- **Preferences** — units, theme, safety-checklist skip.

### Design (2D)
- **Create** — rectangle, circle, line, polyline (click-to-close), text (glyphs → curves, text on curve for signs).
- **Edit** — select / drag-move / multi-select (⌘/⇧), node editing (vertex drag), measure tool, undo/redo.
- **Operations** — Offset, Weld, Subtract, Intersect, Join, Close, Trim, Fillet, Extend, Array copy, Circular copy, Keyhole.
- **Transforms** — nudge, flip horizontal, rotate 90°, scale.
- **Layers** — create/rename/remove/reorder, per-layer hide & lock, layer-faithful save/open.
- **Import / export** — SVG and DXF (LINE/Polyline/Circle/Arc) import, bitmap trace, DXF & STL export.

### Model & 3D (lean spine)
- **STL → relief** — real ASCII-STL parser + triangle rasterizer turns a mesh into a heightfield grid.
- **Bitmap → relief** — grayscale bitmap to heightfield.
- **Model stage** — grayscale relief view with pan/zoom camera, grid/peak readout, contour strip, Reset View.
- **Sculpt mode** — interactive heightfield sculpting strokes (v1).
- **3D toolpaths** — Rough 3D and Finish 3D from the heightfield, rest machining (z-level allowance) support.

### Toolpaths (CAM)
- **Profile** — cut type (in/out/on), climb/conventional, pass depths, tabs, ramping, lead-in/out, corner sharpening, ordering & start-point strategies, allowance.
- **Pocket** — offset/raster fill, multi-tool clearance, profile pass, allowance, ramping, pass control.
- **Drill** — peck cycles (fixed/relative retract), dwell at bottom, plunge feeds.
- **V-Carve** — per-vector depth shading, V-bit angle presets, flat-depth mode, clearance-tool pass before the V-bit, corner sharpen.
- **Specialty** — Quick Engrave, Inlay (pocket/plug + V-carve inlay recipes 30/45/60/90°), Drag Knife (blade-offset pivot arcs), Photo V-Carve (brightness → depth raster), Texture (parallel/crosshatch grooves), Fluting, Prism, Chamfer, Sketch Carve.
- **Tool database** — 13 tool classes, 17 strategy defaults, 3-part cut-data linkage (geometry / per-material / per-machine) with resolved feeds, plunge, RPM (`M3 S…`) and depth.
- **Tree & safety** — toolpath tree with per-op params, dirty flags, recalc-all, keep-out zones, time estimates, group-by-tool export, dirty-export blocking.

### Preview
- Full-tree wireframe overlay, selected-op highlight, sheet-aware material/heightfield simulation that removes stock along cut moves — cancellable and non-blocking.

### Machine control
- **Transports** — built-in simulator plus real serial (GRBL / FluidNC over USB).
- **Operation** — jog, home, set work zero, stream G-code, Hold / Resume / Reset realtime, raw TX/RX console.
- **Safety** — preflight checklist gates Start, zero bytes on load (no auto-run), disconnect stops the stream, E-stop / Reset always visible.

### Platform & UX
- **Stage rail** — Setup → Design → Model → Cut → Preview → Machine, capped at 12 icons per stage.
- **⌘K command palette** — searchable commands including Import SVG/DXF/STL.
- **Context coach** — stage-aware tips with follow-source warnings.
- **GRBL post** — full-tree export with mm/inch variants.

> Roadmap (not yet shipped): double-sided/rotary jobs, advanced 3D component compositing, laser strategies, Post Studio, App Store distribution — tracked in [`docs/planning/FEATURE_PARITY_MATRIX.md`](docs/planning/FEATURE_PARITY_MATRIX.md).

---

## Download

Grab the prebuilt app — no build required:

1. Download [`dist/ShopPilot-macOS.zip`](dist/ShopPilot-macOS.zip) (universal: Apple Silicon + Intel, ad-hoc signed).
2. Unzip and drag **ShopPilot.app** into your Applications folder.
3. First launch from another Mac: **right-click → Open** (Gatekeeper), or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/ShopPilot.app
   ```

*The zip is rebuilt from source with [`scripts/package_app.sh`](scripts/package_app.sh) — the unpacked `.app` is deliberately not committed.*

---

## Build from source

Requires **Xcode 15+** (macOS 14+ SDK). Command Line Tools alone are not enough for the test suite.

```bash
# Build (debug)
swift build

# Run
swift run ShopPilot

# Full test suite (requires full Xcode — see AGENTS.md)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
```

Release build (used by the packaging script):

```bash
swift build -c release --product ShopPilot
./scripts/package_app.sh          # → dist/ShopPilot-macOS.zip (universal)
```

> ⚠️ Use `./scripts/swift_locked.sh build` when multiple agents/terminals may build simultaneously — it serializes Swift invocations.

---

## First 15 minutes

1. **Setup** — pick a recipe (Signage, Decorative Panel, Portrait Relief) or set your own stock.
2. **Design** — draw with Rect / Circle / Line / Polyline, or import **SVG / DXF / STL**. Use the ops bar (Weld, Subtract, Intersect, Join, Close, Trim) and layers.
3. **Cut** — add Profile, Pocket, Drill, or V-Carve toolpaths. Edit art → toolpath goes **dirty** → recalculate before export.
4. **Preview** — simulate the cut (wireframe / heightfield / combined) before you ever touch the machine.
5. **Machine** — connect to the **Simulator** first, pass the preflight checklist, run. Then do the same on real hardware via serial.

Full walkthrough: [`docs/planning/TUTORIAL_FIRST_CUT.md`](docs/planning/TUTORIAL_FIRST_CUT.md)

---

## Where to work

| Doc | Role |
| --- | --- |
| [`docs/planning/TUTORIAL_FIRST_CUT.md`](docs/planning/TUTORIAL_FIRST_CUT.md) | **End-user first-cut tutorial** |
| [`docs/planning/README_MAC_NATIVE.md`](docs/planning/README_MAC_NATIVE.md) | Product overview & feature tiers |
| [`MASTER_KANBAN.md`](MASTER_KANBAN.md) | **Only task board** — claim SPK cards here |
| [`docs/planning/FINISH_ROADMAP.md`](docs/planning/FINISH_ROADMAP.md) | How-to-finish roadmap (Tracks 1–6) |
| [`SHIP_CHECKLIST.md`](SHIP_CHECKLIST.md) | v1 gate checklist |
| [`AGENTS.md`](AGENTS.md) | Agent protocol + safety rules |

---

## Status (honest)

We are **not** at v1.0 yet. Prior Kanban marks overstated completion; the board was repaired 2026-08-01.

- Finish definition = **Engine + UI + Persist + Verify** per card.
- P0 spine: **SPK-1100 → 1106** (session → design → import/export → toolpaths → preview → machine).
- H–K backlog gated on **SPK-0623** (owner decision).
- A full shakedown sweep runs **78 verify targets** green (`./scripts/run_overnight_shakedown.sh` → `results/CLTS.md`).

## Stack

SwiftUI · macOS 14+ · `ShopPilot` (app) · `ShopPilotCore` (engine) · `ShopPilotSerial` (transport) · `ShopPilotGeometry` (geometry) · `ShopPilotTests`

## License

Proprietary — see `LICENSE`. All code and documentation written from scratch; **no Vectric proprietary assets** (no CRV/clipart/paid samples) are used in this project.

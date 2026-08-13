# ShopPilot screenshots (GitHub + Hermes pack)

Images in this folder are the **product gallery**. Hermes **SPK-1700d** captures live windows with `scripts/capture_window.swift <pid> docs/screenshots/<name>.png`. Until that card lands, GitHub uses the **current** numbered shots (they exist) plus captions for the **required pack** (files may be missing).

Do not invent Metal chip-removal stills. Preview is a **2.5D heightfield** (filled raster after 1700a), not a GPU mill sim.

## Current (in repo now)

| File | Stage | Composition |
| --- | --- | --- |
| `01-setup.png` | Setup | Stock / recipe card; six-stage rail visible. |
| `02-design-signage.png` | Design | Vectors/layers; Signage or sample art on canvas. |
| `03-cut.png` | Cut | Toolpath tree + strategy (Profile/Pocket/V-Carve). **Not** laser. |
| `04-model.png` | Model | Relief / empty-state with Rough 3D / Finish 3D — heightfield, not Fusion. |
| `05-machine.png` | Machine | **Simulator** transport; **Hold** and **Reset** visible. |
| `06-preview.png` | Preview | Sheet + wireframe and/or sparse height samples (**pre-1700a**). Replace with filled raster when 1700d ships. |

## Required pack (Hermes 1700d)

| File | Composition (must match) |
| --- | --- |
| `welcome.png` | First-run / **Start Making** Welcome: bundled **samples** (sign, box, keychain, plaque — whatever the sheet lists). Stage rail or Welcome chrome; no laser CTA. |
| `design.png` | **Design** stage: canvas with real vectors (sample or rectangle), layers/inspector. Rail shows Design selected. |
| `cut.png` | **Cut** stage: Pocket or Profile on a closed rectangle (or sample); tree shows the op. Recipes/strategies are CNC (no laser product). |
| `2d-pocket-stepover.png` | **Preview** after 2D pocket (or sample cut) **Simulate**: **filled** heightfield, stepover ridges consistent with **bit-radius stamp** (not 1-cell needles, not `/40` dots). |
| `2d-playhead.png` | Same 2D job, Preview **playhead/slider** mid-sim (partial material removal vs full pocket). Slider visible in chrome. |
| `3d-relief-sim.png` | Plaque sample or STL/heightfield → **Rough 3D** (Finish optional) → Preview Simulate: relief carved in the heightfield. Not an empty Model placeholder. |
| `machine-sim.png` | **Machine** + **Simulator** connected; G-code loaded or idle; **Hold** + **Reset** always visible. Never Serial/USB. |

## Capture

```bash
# after swift_locked build --product ShopPilot
swift scripts/capture_window.swift "$PID" docs/screenshots/welcome.png
```

Screen Recording permission required for `screencapture -l`. Simulator only.

## README wiring

Root `README.md` **Screenshots** section points here. After 1700d, Hermes updates image markdown to the required filenames (and may keep `01–06` as aliases or replacements).

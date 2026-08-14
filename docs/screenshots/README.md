# ShopPilot screenshots (GitHub pack)

Images here are the **product gallery**. Required pack landed with **SPK-1700d**. Preview is a **filled 2.5D heightfield + playhead**, not a GPU mill / Metal chip sim. No laser CTAs.

## Required pack (README wires these)

| File | Composition |
| --- | --- |
| `welcome.png` | Welcome / **Start Making**: bundled samples (sign, box, keychain, plaque). No laser CTA. |
| `design.png` | **Design**: vectors on canvas, layers/inspector; rail on Design. Snap / DRO / origin may be visible. |
| `cut.png` | **Cut**: Pocket or Profile (or sample); recipes are CNC (no laser product). |
| `2d-pocket-stepover.png` | **Preview** after 2D pocket **Simulate**: filled heightfield, stepover ridges from **bit-radius stamp**. |
| `2d-playhead.png` | Same job, **playhead** mid-sim; slider visible. |
| `3d-relief-sim.png` | Plaque / STL heightfield → Rough 3D → Preview: relief in the heightfield. Not Fusion. |
| `machine-sim.png` | **Machine** + **Simulator**; **Hold** + **Reset** visible. Not Serial/USB. |

## Numbered aliases (still in repo)

| File | Stage |
| --- | --- |
| `01-setup.png` | Setup |
| `02-design-signage.png` | Design |
| `03-cut.png` | Cut |
| `04-model.png` | Model (2.5D relief / orbit — not Fusion) |
| `05-machine.png` | Machine simulator |
| `06-preview.png` | Preview heightfield |

## Capture

```bash
# after swift_locked build --product ShopPilot
swift scripts/capture_window.swift "$PID" docs/screenshots/welcome.png
```

Screen Recording permission required for `screencapture -l`. Simulator only.

# ShopPilot — First Cut Tutorial

**Audience:** New users with a Mac and (optionally) a CNC machine.
**Time:** ~15 minutes, **simulator only** — no hardware required.

---

## Goal

From install → sample or recipe → G-code → **simulator** stream. Live serial is optional and is **not** the bar.

Model orbit is a thin 2.5D relief view. Preview is a filled heightfield + playhead.

---

## Prerequisites

- macOS 14+ (Apple Silicon or Intel)
- ShopPilot **0.06** — [`dist/ShopPilot-0.06-macOS.zip`](../../dist/ShopPilot-0.06-macOS.zip) or `VERSION=0.06 ZIP_NAME=ShopPilot-0.06-macOS.zip ./scripts/package_app.sh` (see [README](../../README.md))
- Optional: USB serial CNC (Step 8)

---

## Step 1 — Welcome / Setup

1. Launch ShopPilot. First run: **Welcome / Start Making** with bundled samples (sign, box, keychain, plaque). **Try a sample**, or close Welcome and use Setup.
2. On **Setup**, pick a **recipe** (Signage, Decorative Panel, Portrait Relief) or set **Material** and **Stock** yourself.
3. Advanced (sheets, double-sided, rotary, document variables) stays collapsed unless you need it.

![Welcome samples](../screenshots/welcome.png)

![Setup stage](../screenshots/01-setup.png)

---

## Step 2 — Design

Switch to **Design**.

1. Draw with **Rect / Circle / Line / Polyline**; add text; or **Import** SVG / DXF / STL.
2. **Snap to grid** (toolbar) so create/move land on the grid.
3. **Select**: drag empty space for a **marquee**; hold **Space** (or middle-button) to pan.
4. Watch the **XY DRO** (sheet mm). Set **sheet origin** (corner vs center) if your job is not lower-left (0,0).
5. Ops: Weld / Subtract / Intersect / Join / Close / Trim, plus nudge/flip/rotate/scale.

![Design stage](../screenshots/design.png)

---

## Step 3 — Cut

Switch to **Cut**.

1. Recipes: **Cut out** (Profile), **Pocket**, **Engrave**, or **More**.
2. Inspector shows **F / S / Z** for the selected op. Tabs/leads for Profile also show on the Design overlay.
3. Generate/recalc is **async** — the window should stay responsive.
4. **Dirty workflow:** edit art → toolpath goes dirty → export blocked until Recalculate.

![Cut stage](../screenshots/cut.png)

---

## Step 4 — Preview

Switch to **Preview**.

1. **Simulate**. You get a **filled 2.5D heightfield** (and wireframe / combined toggles).
2. Use the **playhead / Play** to scrub sim time (empty stock → full removal).
3. **Cancel** aborts a long sim.

![Preview pocket](../screenshots/2d-pocket-stepover.png)

![Preview playhead](../screenshots/2d-playhead.png)

---

## Step 5 — Model (optional)

**Model** is heightfield relief (STL / plaque / 3D text) plus **Rough 3D / Finish 3D**. **Orbit** looks around the relief in 2.5D.

![Model stage](../screenshots/04-model.png)

![3D relief in Preview](../screenshots/3d-relief-sim.png)

---

## Step 6 — Simulator (the bar)

1. **Machine** stage. Transport: **Simulator**. **Connect**.
2. Send G-code from Cut (**Send to Machine Stage**) or load the air-cut square if the buffer is empty.
3. Acknowledge **Pre-Flight**. **Hold / Resume / Reset** stay visible.
4. **RUN**. Simulator waits for `ok` per line. No auto-run on load.
5. Large **Machine DRO** shows parsed position.

![Machine simulator](../screenshots/machine-sim.png)

> Software Hold/Reset complements but does not replace a hardware e-stop.

---

## Step 7 — Save / export

- **Save / Open** `.shoppilot` (vectors, layers, toolpaths).
- **Export G-code** from Cut — blocked while dirty.

---

## Step 8 — Real hardware (optional)

Serial to GRBL/FluidNC exists (port + baud). After Connect: jog, zero, preflight, then Run. First moves should be **air cuts**. Keep a hardware e-stop in reach. This step is optional; **personal acceptance is simulator-first**.

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Dirty toolpath — cannot export | Recalculate in Cut after editing art |
| Toolpaths missing on canvas | Select vectors before calculating |
| Simulator won't connect | Transport = Simulator, then Connect |
| Alarm / soft-limit | **Reset**, re-home, smaller jog |
| Toolpath outside stock | Fix stock in Setup |

---

## What's next?

- Other samples and recipes (Decorative Panel, Portrait Relief).
- Safety: [`SAFETY.md`](SAFETY.md).
- Agents: `MASTER_KANBAN.md`. **SPK-0623** stays owner-gated until the owner marks it.

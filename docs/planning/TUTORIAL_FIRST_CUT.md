# ShopPilot — First Cut Tutorial

**Audience:** New users with a Mac and (optionally) a CNC machine.  
**Time:** ~15 minutes, simulator only — no hardware required.

---

## Goal

Take you from "ShopPilot is installed" to "I've generated G-code and streamed it through the simulator" — safely, without touching real hardware.

---

## Prerequisites

- macOS 14+ (Apple Silicon or Intel)
- ShopPilot installed — download [`dist/ShopPilot-macOS.zip`](../../dist/ShopPilot-macOS.zip) or build from source (see [README](../../README.md))
- Optional: a CNC machine connected via USB serial (Step 8)

---

## Step 1 — Create a Job (Start with a Recipe)

1. Launch ShopPilot. You land on the **Setup** stage.
2. Click the **Choose a Recipe** card.
3. Pick **Signage**. ShopPilot creates the job, a sign-shaped sheet, and even pre-generates a V-Carve toolpath (you'll see "Recipe V-Carve ready" in the status bar).
4. Set your material: choose a **Material** and confirm **Stock Dimensions** (width / depth / height in mm).

> ✨ Recipes give you a complete, working job in one click — the fastest way to learn the pipeline. You can also start with a blank **Custom** job and set stock yourself.

![Setup stage](../screenshots/01-setup.png)

---

## Step 2 — Design (Vectors & Layers)

Switch to the **Design** stage. The Signage recipe already placed your art on layers.

1. Look at the **LAYERS** panel (left): `Text` (4 items) and `Border` (1 item).
2. Draw your own shape with the **Rect**, **Circle**, **Line**, or **Polyline** tools.
3. Use the **Ops bar** for vector surgery: **Weld / Subtract / Intersect / Join / Close / Trim**, plus Nudge, Flip, Rotate, Scale.
4. Import artwork anytime: **SVG**, **DXF**, or **STL relief** (Design → STL Relief…).

![Design stage](../screenshots/02-design-signage.png)

---

## Step 3 — Cut (Toolpaths)

Switch to the **Cut** stage.

1. **+ Add Toolpath** → choose a strategy:
   - **Profile** — cut around the outline (on/inside/outside line)
   - **Pocket** — clear an enclosed area
   - **Drill** — plunge holes
   - **V-Carve** — engrave with a V-bit (the recipe already made one for you)
2. Pick the vectors to cut, choose a **Tool**, set depth / feed / passes.
3. Click **Calculate** — the toolpath appears in the list and on canvas.

**Dirty workflow (important):** edit your design after generating a toolpath and it goes **dirty** ("Recalculate Dirty (1)"). Export is blocked until you **Recalculate** — this protects you from cutting stale art.

![Cut stage](../screenshots/03-cut.png)

---

## Step 4 — Preview (Simulate Before You Cut)

Switch to the **Preview** stage.

1. Select a toolpath and click **Simulate**.
2. Watch the virtual cutter remove material — toggle **Wireframe / Heightfield / Combined** views.
3. Run the draft simulation; **Cancel** aborts a long sim.

![Preview stage](../screenshots/06-preview.png)

---

## Step 5 — Model (3D Relief, Optional)

The **Model** stage shows 3D relief and offers **Rough 3D / Finish 3D** toolpaths (Studio3D tier). Import an STL in Design → STL Relief… to populate it.

![Model stage](../screenshots/04-model.png)

---

## Step 6 — Run on the Simulator (No Hardware)

1. Switch to the **Machine** stage.
2. Transport: **Simulator** (default). Click **Connect** — status turns green **Connected**.
3. Send your toolpath: **Send to Machine Stage** in Cut (or the air-cut square loads automatically if the buffer is empty).
4. Work through the **Pre-Flight Checklist** — all items must be acknowledged.
5. Click **RUN**. The simulator streams the G-code line-by-line (each line gets an `ok`) and reports **Stream complete**.
6. After a run, the checklist returns — you can adjust and run again.

![Machine stage](../screenshots/05-machine.png)

> Safety chrome: **Hold / Resume / Reset** are always visible while connected — no auto-run on load, ever.

---

## Step 7 — Save, Open, Export

- **Save / Open** (`.shoppilot` package) — job, layers, toolpaths, and machine profile all round-trip.
- **Export G-code** — GRBL-compatible output, blocked while any toolpath is dirty.
- Export happens through the Cut stage (**Save Toolpaths…** / **Send to Machine Stage**).

---

## Step 8 — Real Hardware (Optional)

1. Connect your CNC via USB serial.
2. Machine stage → Transport: **Serial** → **Connect**.
3. Set work zero with the **Jog** pad + **Zero X / Y / Z**.
4. Re-run the preflight checklist — all green.
5. Clamp material, confirm the tool, click **RUN**.

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| "Dirty toolpath — cannot export" | Recalculate in the Cut stage after editing art |
| Toolpaths don't appear on canvas | Select vectors in the Cut stage's vector selector before calculating |
| Simulator won't connect | Ensure Transport = Simulator, then Connect |
| Machine shows alarm / soft-limit | Press **Reset**, re-home, reduce jog step, retry |
| "Toolpath outside stock bounds" | Fix stock dimensions in Setup to match your material |

---

## What's Next?

- Import an **SVG/DXF** instead of drawing (Design stage, Import Design File).
- Try the **Decorative Panel** and **Portrait Relief** recipes for different workflows.
- Read the [product overview](README_MAC_NATIVE.md) for the full feature map.
- Check `MASTER_KANBAN.md` for what's shipping next.

# ShopPilot — First Cut Tutorial

**Date:** 2026-07-28  
**Audience:** New users with a Mac and (optionally) a CNC machine.

---

## Goal

Take you from "ShopPilot is installed" to "I've generated G-code for my first job" in under 15 minutes.

---

## Prerequisites

- macOS 14+ on Apple Silicon or Intel
- ShopPilot installed (download from releases or App Store)
- Optional: A CNC machine connected via USB serial cable

---

## Step 1 — Create a New Job

1. Launch ShopPilot. You'll see the **Setup** stage with a blank canvas.
2. Click **New Job** (or ⌘N).
3. In the Job Setup dialog:
   - **Stock width:** `100` mm
   - **Stock depth:** `100` mm  
   - **Stock height:** `12` mm
   - **Units:** Millimeters
   - **Origin:** Center
4. Click **Create**.

You now have a virtual piece of material to work with.

---

## Step 2 — Draw Your Design

Switch to the **Design** stage (click "Design" in the stage rail at the top).

1. Select the **Rectangle** tool from the left toolbar (or press R).
2. Click and drag on the canvas to draw a rectangle roughly centered on your stock.
3. With the rectangle selected, open the **Inspector** panel (right side) and set:
   - **Width:** `60` mm
   - **Height:** `40` mm
4. Select the **Offset** tool (or press O). Set offset to `2` mm and click Apply. This creates a border around your rectangle — perfect for a simple sign or plaque outline.

---

## Step 3 — Add Text

1. Select the **Text** tool (or press T).
2. Click inside your offset shape and type something like "HELLO".
3. In the Inspector, choose a font (system fonts are available by default) and set size to `14` pt.
4. With the text selected, go to **Object → Text to Curves** (or ⌘T). This converts editable text into vector paths that can be toolpathed.

---

## Step 4 — Generate Toolpaths

Switch to the **Cut** stage.

### Profile Toolpath (cutting the outline)
1. Click **+ Add Toolpath** → select **Profile**.
2. In the Vector Selector, click your offset rectangle.
3. Configure:
   - **Tool:** End mill 6mm (default — adjust in Tool Database if needed)
   - **Cut type:** On line
   - **Depth:** `-2` mm (cuts 2mm deep into stock)
   - **Feed rate:** `800` mm/min
4. Click **Calculate**. You'll see the toolpath preview on the canvas in green.

### V-Carve Toolpath (engraving text)
1. Click **+ Add Toolpath** → select **V-Carve**.
2. In the Vector Selector, click your text curves.
3. Configure:
   - **Tool:** V-bit 90° (select from tool dropdown)
   - **Depth:** `-1` mm
   - **Feed rate:** `500` mm/min
4. Click **Calculate**. The toolpath preview shows in blue.

---

## Step 5 — Preview Simulation

Switch to the **Preview** stage.

1. Select both toolpaths (click one, then ⌘-click the other).
2. Click **Simulate** (or press Space).
3. Watch the material simulation animate — you'll see the virtual cutter removing material layer by layer.
4. Toggle between **Draft** and **Final** preview modes to see progressive refinement.

---

## Step 6 — Export G-Code

1. With your toolpaths selected, click **Export G-Code**.
2. Choose a save location (e.g., `~/Desktop/hello.nc`).
3. The file is GRBL-compatible and ready for your machine controller.

---

## Step 7 — Run on Simulator (No Hardware Required)

1. Switch to the **Machine** stage.
2. In the Transport dropdown, select **Simulator**.
3. Click **Connect** → then **Load File** → select your `hello.nc`.
4. Review the preflight checklist (should show all green).
5. Click **Run**. The simulator will stream through your G-code and report completion.

---

## Step 8 — Run on Real Hardware (Optional)

1. Connect your CNC machine via USB serial cable.
2. In the Machine stage, select **Serial** transport.
3. Choose the correct port (ShopPilot auto-detects available ports).
4. Click **Connect**.
5. Set your work zero using the Jog controls (X, Y, Z axes).
6. Review the preflight checklist — all items must be green.
7. Ensure the material is securely clamped and the correct tool is loaded.
8. Click **Run** to start cutting.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Toolpath outside stock bounds" | Check stock dimensions in Setup stage match your physical material |
| "Dirty toolpath — cannot export" | Click Recalculate after making design changes |
| "No machine connected" | Use Simulator transport for testing, or check USB cable connection |
| Toolpaths don't appear on canvas | Make sure vectors are selected in the Vector Selector panel |

---

## What's Next?

- Try importing an SVG file (File → Import) instead of drawing from scratch.
- Explore the **Model** stage for 3D relief work (requires Studio3D license).
- Check out [KEYBOARD_SHORTCUTS.md](./planning/KEYBOARD_SHORTCUTS.md) to speed up your workflow.

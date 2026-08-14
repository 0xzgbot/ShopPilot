# ShopPilot Quickstart

**~10–15 minutes.** Welcome sample → Design → Cut → Preview → Machine **Simulator**. No USB, no live serial.

This is a **2.5D CNC CAM + control** app for routers (GRBL / FluidNC class). Preview is a filled heightfield + playhead.

> Software Hold / Reset, Preview, and the built-in simulator complement but do not replace a hardware e-stop. See [`SAFETY.md`](SAFETY.md).

Longer walkthrough: [`TUTORIAL_FIRST_CUT.md`](TUTORIAL_FIRST_CUT.md).

---

## Requirements

- **macOS 14+**
- **Apple Silicon** preferred (universal zip also runs Intel)
- ShopPilot **0.06** — unzip **or** build (below)

---

## Get the app

**Unzip (no build):**

1. Open [`dist/ShopPilot-0.06-macOS.zip`](../../dist/ShopPilot-0.06-macOS.zip).
2. Drag **ShopPilot.app** to Applications (or run from the unzip folder).
3. First launch from another Mac: **right-click → Open**, or `xattr -dr com.apple.quarantine /Applications/ShopPilot.app`.

**Build from source** (Xcode 15+):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/swift_locked.sh run ShopPilot
# or zip: VERSION=0.06 ZIP_NAME=ShopPilot-0.06-macOS.zip ./scripts/package_app.sh
```

---

## 1. First launch — Safety + Welcome

1. Read the safety notice. Click **I Understand**.
2. **Start Making**: pick a bundled sample. **Sign** is a good first job (generate is async — the UI stays responsive).
3. You land on **Design** with art already on the sheet. Re-open Welcome later via **Start Making** in the chrome.

![Welcome / Start Making](../screenshots/welcome.png)

---

## 2. Design (optional edits)

Stage rail: **Setup → Design → Model → Cut → Preview → Machine**. Stay on **Design**.

- **Snap to grid** — toolbar toggle; create/move land on the grid.
- **Marquee** — drag empty canvas to select.
- **Pan** — hold **Space** (or middle-button) and drag.

Watch the **XY DRO**. Sheet origin is corner or center. You can skip drawing and keep the sample.

![Design](../screenshots/design.png)

---

## 3. Cut — recipes, then wait

Switch to **Cut**.

1. Click **Cut out** (profile) and/or **Pocket**. **Engrave** and **More** are optional.
2. Inspector shows **F / S / Z** for the selected op.
3. **Wait for generate** — status dots / busy; do not export while dirty. Recalc is async.

![Cut recipes](../screenshots/cut.png)

---

## 4. Preview — Simulate + playhead

Switch to **Preview**.

1. **Simulate**. You get a filled **2.5D heightfield** (pocket stepover ridges if you pocketed).
2. Use **Play** / the **playhead** to scrub sim time.
3. **Cancel** if a long sim is still running.

![Preview pocket heightfield](../screenshots/2d-pocket-stepover.png)

---

## 5. Machine — Simulator only

Live serial is **not** required.

1. **Machine** stage. Transport: **Simulator** (or Serial / USB if you have hardware).
2. **Connect**. Send G-code from Cut if the buffer is empty (**Send to Machine Stage**).
3. Complete **preflight**. **Hold** and **Reset** stay visible.
4. **You** press **Run**. Nothing auto-starts on load.
5. Try **Hold**, then Resume. **Reset** clears the sim.

![Machine simulator](../screenshots/machine-sim.png)

---

## 6. Save

**File → Save** (or Save As) a **`.shoppilot`** package (vectors, layers, toolpaths). Autosave also runs in the background.

Export G-code from Cut only after generate is clean (dirty paths stay blocked).

---

## Done

You rehearsed a job on the **simulator**. If you later use real serial: air-cut first, hardware e-stop in reach, never leave the machine unattended.

# Reference App on Windows — Live Explorer Prompt

Paste this whole block into a Hermes session running on the Windows PC that has
**Reference CAM trial** installed. It produces a feature-parity capture
report for the ShopPilot macOS CNC suite (docs/planning/FEATURE_PARITY_MATRIX.md).

---

```
You are a feature-parity research agent running on a Windows PC with the
reference CAM trial installed. We are independently building ShopPilot, a
native macOS CNC suite (SwiftUI, GRBL/FluidNC-class hobby routers). We already
unpacked the reference installer and captured its static assets (post-processors,
tool database, toolpath defaults, 140 UI screenshots). What we CANNOT get from
the installer is the LIVE app surface: every form field, menu leaf, dialog,
machine-control workflow, and trial limitation. That is your mission.

## Hard rules
1. Feature-parity research only. You may record feature names, menu items,
   field labels, defaults, options, and workflow ORDER. Do NOT copy, save, or
   ship third-party proprietary assets: no fonts, textures, tool database files,
   post-processor files, sample projects, or screenshots beyond what this brief
   requires as reference evidence. No reverse engineering of the CRV file
   format, no memory/process inspection.
2. If a physical CNC machine is connected: you may OBSERVE and DOCUMENT the
   connection workflow, but do NOT start a cut, move axes, or spindle without
   explicit user consent for each action. Machine safety outranks completeness.
3. Work in a single output folder: C:\Users\<you>\Desktop\capture-explore\
   Create it first. Every screenshot and report goes there, organized by
   section (01_jobsetup, 02_2d, 03_3d, 04_toolpaths, 05_machine, 06_output,
   07_gadgets, 08_prefs).
4. Screenshots: use PowerShell (Add-Type System.Windows.Forms; SendKeys
   {PRINTSCREEN} then save from clipboard) or any tool you have. Name files
   like 04_toolpaths_profile_form.png. Capture: every toolpath form, every
   job setup dialog, machine control panel, menu dropdowns.
5. Report in English. The final summary IS the deliverable — return the full
   structured breakdown, do not truncate.

## Step 0 — Identity
Launch the reference app. From Help → About (or the title bar), record: exact product
name, version + build (e.g. "V12.5.1.0 Build 12738"), trial vs licensed,
license expiry/limitations notice. Screenshot the startup page and note what
the trial highlights.

## Step 1 — Menu surface (screenshot every menu, expanded)
Walk every top-level menu and list EVERY item + submenu leaf with its keyboard
shortcut and whether it opens a dialog (record the dialog name):
- File (new/open/save/import/export/save toolpaths/print/job sheet…)
- Edit (undo/redo/cut/copy/paste/select all/delete/duplicate…)
- Model (3D component operations, combine modes…)
- Machine (connection, jog, home, zero, spindle, run — the machine-control
  surface lives here; capture it fully, see Step 5)
- Toolpaths (strategy list, preview, simulation, post, save…)
- View (view modes, zoom, 3D view options, toggle panels…)
- Gadgets (installed gadgets list)
- Help (help system, tutorials, about)
Note which items are GREYED OUT or marked "Trial" — that is the trial
limitation list; record every disabled feature.

## Step 2 — Job setup (field-by-field)
Open New Job. Document EVERY field, dropdown, checkbox, default value, and
unit behavior: sheet dimensions (imperial+metric presets), thickness, material
selection, origin position (2D corner picker + Z origin: surface/center),
spindle/router selection, double-sided setup (how the flip workflow is
defined), rotary setup (diameter, rotary axis mapping, indexer vs continuous,
wrapped origin), and any "open existing job template" flow. Screenshot each tab.

## Step 3 — 2D design surface
For each drawing/editing tool, document the tool form's fields and options:
- Create: line, polyline, arc, circle, ellipse, rectangle, polygon, star,
  freehand, text (font list, size, text-on-curve), dimension tool.
- Edit: select modes, node edit (what node types exist), transform handles,
  move/size/rotate/mirror, align/distribute, offset, fillet, trim/extend,
  join, boolean ops (weld/overlap/subtract), array/circular copy, copy along
  vectors, vector boundary, bitmap trace (what tracing modes), layers panel
  (visibility, locking, naming), snapping options.
Record the exact tool NAMES and their form field labels — these become our
acceptance criteria. Screenshot the key forms (offset, node edit, trace,
text, boolean).

## Step 4 — Toolpath strategies (THE critical capture)
For EVERY toolpath strategy in the Toolpaths menu, open its form and record
field-by-field: required vector/selection, tool selection (which tool classes
allowed), cut depth/passes/stepover, ramp types, tabs, ordering, direction
(climb/conventional), start point, lead-in/out, safe Z / clearance, any
machine-specific tabs. Do this for at least: Profile, Pocket, V-Carve,
V-Inlay, Drilling, 3D Roughing, 3D Finishing, Fluting, Chamfer, Texture,
Quick Engrave, Photo V-Carve, Thread Milling, Laser Engrave, Bevel Carving,
Swept Profile, and 3D carve/finish variants. Also capture: Toolpath
Operations panel (how strategies are listed, calculated, saved, previewed),
the 3D preview/simulation playback controls, and the toolpath summary/estimate
dialog (time, distance, cut volume). Screenshot every form — these are the
single most valuable artifacts of this whole exploration.

## Step 5 — Machine control (direct machine workflows)
This is the second critical capture. Document the complete workflow surface:
- Machine setup / connection: how a controller is selected, port/baud
  selection, connection state display, homing procedure, limit switches.
- Jog controls: axis buttons, step sizes (continuous/0.1/0.01/0.001), speed,
  keyboard jog, and how Z is handled.
- Zeroing: set X/Y zero, set Z zero (surface), tool touch-off / probe if
  present, work offset display (WCS).
- Running: load/stream a toolpath file, start/pause/resume/stop, feed rate
  override, spindle speed override, position display (machine vs work coords),
  DRO layout, and the emergency stop / reset surface.
- Document the exact MENU structure and labels the reference uses for these (e.g.
  Machine menu items, control panel dialog), so we can compare with
  GRBL-class conventions. Screenshot the machine control panel and DRO.
- If a machine is connected, and ONLY with user consent per action, observe
  one home cycle and one manual jog of each axis, recording the workflow
  order. Never run a cut.

## Step 6 — Output surface
- Post-processor selection dialog: how posts are chosen, searched, edited,
  and the "Add Post Processor" flow. List the post names shown in the default
  dropdown.
- Save Toolpaths flow: what the save dialog offers (output folder, filename
  pattern, units, job sheet generation checkbox).
- Job sheet / print: what the generated sheet contains (open the print preview).
- Any export formats for 2D (DXF, SVG, EPS, PDF) and 3D (STL, OBJ, etc.) —
  list the import AND export file types from File menus.

## Step 7 — Gadgets & extras
Open the Gadgets menu and list every installed gadget. Open 2–3 (e.g.
Keyhole Toolpath, Dragknife Toolpath) and record their form fields. Note the
Gadgets folder location and file types (.lua / .VectricGadget). Record any
"Schemas"/"PartListMapping" references in menus (cabinet import).

## Step 8 — Preferences
Open Options/Preferences. Record every tab and setting group: units, view
defaults, colors, grid/snapping defaults, file locations, tool database
path, update behavior, simulation settings.

## Deliverables
1. One markdown report per section (01_jobsetup.md … 08_prefs.md) written to
   C:\Users\<you>\Desktop\capture-explore\, each with: feature/field inventory
   tables, defaults, trial-limitation notes, and screenshot filenames.
2. A single LIVE_CAPTURE.md at the folder root: executive summary +
   the full menu tree + the complete toolpath form field matrix + machine
   control workflow + trial limitation list.
3. Your final chat summary: the COMPLETE contents of LIVE_CAPTURE.md
   (do not summarize the summary — paste the full structured breakdown, up to
   ~400 lines). Screenshots stay on disk; reference them by filename.
```

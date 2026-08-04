# Aspire Form Defaults — Results Template

**Status:** EMPTY — awaiting Windows capture run (paste `ASPIRE_FORM_DEFAULTS_RUNSPEC.md` into a Hermes session on the Windows PC with Aspire Trial; copy the four form tables here when the report comes back).
**Runspec:** `docs/planning/research/ASPIRE_FORM_DEFAULTS_RUNSPEC.md` · **Merge target when filled:** FEATURE_PARITY_MATRIX.md §R.
**Capture job spec (fixed):** 300×200 mm, 19 mm thick, mm units, datum lower-left, Z0 material surface; rectangle 100×60, circle d=25, text "AaBb" 20 mm; 3D content = rounded dome over rectangle for the 3D forms.

---

## Form 1 — Profile toolpath (on rectangle)

| Field | Default value | Units | Options (verbatim) | Notes |
|---|---|---|---|---|
| Start depth | | | | |
| Cut depth | | | | |
| Tool (pre-selected) | | | | |
| Pass depth | | | | |
| Machine on (inside/outside/on line) | | | | |
| Direction (climb/conventional) | | | | |
| Ramp/plunge (on? length default) | | | | |
| Tabs (length/thickness default, auto-placement options) | | | | |
| Lead-in/out | | | | |
| Advanced section fields (verbatim) | | | | |
| Tool DB default tool: diameter/flutes/feeds/speeds/pass/stepover | | | | |

## Form 2 — V-Carve toolpath (on text)

| Field | Default value | Units | Options (verbatim) | Notes |
|---|---|---|---|---|
| Start depth | | | | |
| Flat depth (checked? value) | | | | |
| Finishing tool defaults | | | | |
| Clearance tool (checked? default tool? offset strategy options) | | | | |
| Vector start points / selection order | | | | |
| Project-to-3D option | | | | |
| Depth-relationship hints shown (angle vs width) | | | | |

## Form 3 — 3D Roughing toolpath (dome over rectangle)

| Field | Default value | Units | Options (verbatim) | Notes |
|---|---|---|---|---|
| Tool (pre-selected) | | | | |
| Machining limit boundary (model/material/vector/level) + default | | | | |
| Boundary offset default | | | | |
| Machining allowance default | | | | |
| Strategy (Z-level vs 3D raster) | | | | |
| Z-level sub-options (profile before/after/none; order level-by-level/depth-first) | | | | |
| Raster angle | | | | |
| Ramp plunge options | | | | |
| Avoid-machined-areas | | | | |
| Vector selector | | | | |

## Form 4 — 3D Finishing toolpath (same content)

| Field | Default value | Units | Options (verbatim) | Notes |
|---|---|---|---|---|
| Tool (pre-selected; ball-nose?) | | | | |
| Boundary limit + offset default | | | | |
| Strategy (offset/raster) + default | | | | |
| Stepover default + units | | | | |
| Stepover retract default | | | | |
| Cut direction default | | | | |
| Rest machining (checked? minimum detail default; extra tool defaults) | | | | |
| Raster angle | | | | |

## Save toolpaths summary (names only)

| Item | Value |
|---|---|
| Default post for GRBL/Shapeoko-class machine (if present) | |
| Default save option (selected/visible/multiple/group) | |
| ATC tool-change check behavior observed | |

# Windows Aspire Live Form Capture — narrow runspec (field defaults only)

**Date:** 2026-08-04 · **Relationship:** complements `docs/planning/WINDOWS_EXPLORER_PROMPT.md` (broad feature-parity capture). This runspec is **narrow**: only the four toolpath forms ShopPilot must match by default — **Profile, V-Carve, 3D Roughing, 3D Finishing**. Skip everything else (gadgets, laser, rotary, clipart, install).
**Prereq:** Windows PC with Vectric Aspire Trial (V12.5) installed. Paste into a Hermes session on that PC.

---

## Runspec (paste to the Windows Hermes session)

```
You are a form-capture research agent on a Windows PC with Vectric Aspire Trial (V12.5).
Target: capture the EXACT default field values of four toolpath forms for ShopPilot
(independently built macOS CNC suite). Record field names, units, defaults, and option
lists. Do NOT copy Vectric assets (no screenshots beyond what this brief needs, no
tool DB files, no posts, no CRV RE).

Output folder: C:\Users\<you>\Desktop\aspire-explore\forms\  (create it)

## What to do
1. Launch Aspire, create a NEW job: 300 x 200 mm, 19 mm thick, inches OFF (mm), datum
   lower-left, Z0 material surface. Draw: a 100x60 mm rectangle, a circle d=25 mm,
   a text string "AaBb" (any font, 20 mm height), and import nothing else.
2. For EACH of the four forms below: open it on the drawn geometry, and record a table:
   Field Name | Default Value | Units | Options (verbatim list) | Notes
   Capture BOTH the untouched defaults AND what changes when you click each option.
   Record the tool selector defaults (which tool is pre-selected, what the tool DB
   shows for the default tool: diameter, flutes, feeds, speeds, pass depth, stepover).

### Form 1 — Profile toolpath
   On the rectangle. Record every field: start depth, cut depth, tool, pass depth,
   machine on (inside/outside/on line), direction (climb/conventional), ramp/plunge
   options + ramp length default, tabs (length/thickness defaults, auto-placement
   options), lead-in/out, any "advanced" section fields and their defaults.

### Form 2 — V-Carve toolpath
   On the text. Record: start depth, flat depth (default value and whether checked),
   finishing tool defaults, clearance tool section (checked? default tool? offset
   strategy options), vector start points / selection order options, project-to-3D
   option, and the depth-relationship hints shown (tool angle vs width).

### Form 3 — 3D Roughing toolpath
   On the rectangle with a 3D component added (use the 3D shape tool: create a
   rounded dome over the rectangle first — that counts as your 3D content). Record:
   tool default, machining limit boundary (model/material/vector/level) + default,
   boundary offset default, machining allowance default, strategy (Z-level vs 3D
   raster) + sub-options (profile before/after/none, order level-by-level/depth-first),
   raster angle, ramp plunge options, avoid-machined-areas, vector selector.

### Form 4 — 3D Finishing toolpath
   Same 3D content. Record: tool default (ball-nose?), boundary limit + offset
   default, strategy (offset/raster) + defaults, stepover default + units, stepover
   retract default, cut direction default, rest machining section (checked? minimum
   detail default, extra tool defaults), raster angle.

3. Also capture ONE save-toolpaths screenshot-level summary: default post processor
   for a GRBL/Shapeoko machine if present in the list (names only), and the default
   save options (selected/visible/multiple/group).
4. Write the report as C:\Users\<you>\Desktop\aspire-explore\forms\FORM_DEFAULTS.md
   with the four tables + save summary. Return the FULL report in your final message
   (do not truncate).

## Rules
- Record field labels VERBATIM (English UI).
- Mark defaults you are unsure about with a "?".
- If a field is hidden behind "Advanced", open it and record its defaults too.
- No machine motion. No cutting. No file copies. Research capture only.
- Timebox: under 60 minutes. If a form is missing in the trial, note "N/A in trial".
```

## How to use the results

- Merge into `docs/planning/research/` as `ASPIRE_FORM_DEFAULTS_CAPTURE.md` (or directly into FEATURE_PARITY_MATRIX.md §R when it lands).
- Diff against ShopPilot's current ProfileToolpath.swift / V-Carve / 3D forms for **default-value parity** (safe defaults > feature parity).
- The V-Carve flat-depth default and 3D machining-allowance default are the two numbers most worth matching (see FAILURE_MODE_LAB FM-06/FM-15).

## Status
NOT YET RUN — requires the user's Windows PC + Aspire trial. When the capture summary comes back, merge per the memory note (FEATURE_PARITY_MATRIX.md §R).

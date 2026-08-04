# Failure-Mode Lab — bad G-code outcomes → preflight rules + preview warnings

**Date:** 2026-08-04 · **Method:** synthesis of 20 Vectric transcripts read in full (getting-started series, V-Carve/clearance, 3D rough/finish, toolpath FAQ, validator, profile/pocket/drill, chamfer) + GRBL dialect research + feeds/speeds sources.
**Relationship to existing docs:** complements `docs/planning/PREFLIGHT_RULES.md` (which maps Aspire *error strings* to vector-geometry preflight). This doc adds the **machine-outcome layer**: what actually breaks on the machine, and which warnings the app should raise before/at preview.
**Notation:** FM-### = failure mode; each has trigger, mechanism, worst case, detection, and the ShopPilot warning to implement.

---

## A. Geometry / toolpath-generation failures (catch in engine, block export)

### FM-01 Open vector in V-Carve
- **Trigger:** open polyline/arc selected for V-Carve (or pocket/profile expecting closed).
- **Mechanism:** tool runs down the center of "opposing vectors" — an open chain has no closed region; depth undefined.
- **Worst case:** garbage toolpath or error at post.
- **Detection:** closed-ness check at toolpath calculation.
- **ShopPilot rule:** mirror Aspire's enforced error — *"V-carving can only be done with closed vectors."* Block, highlight gap endpoints, offer Join. (PREFLIGHT_RULES R001.)

### FM-02 Duplicate / overlapping contours
- **Trigger:** import (or trace) produces two coincident vectors; user welds nothing.
- **Mechanism:** tool cuts the same path twice; or pocket fill double-cuts; chatter on second pass.
- **Worst case:** doubled cut time, tear-out on the second pass, broken small features.
- **Detection:** vector validator (overlaps/intersections count).
- **ShopPilot rule:** warning on import (validator auto-run); *"this shape is duplicated — you'll cut it twice."* (R004.)

### FM-03 Self-intersecting contour
- **Trigger:** figure-eight / crossing contour from a bad trace or node edit.
- **Mechanism:** toolpath generator can't compute an inside/outside; may cut in two places at once.
- **Worst case:** tool plunges through the crossing, gouge.
- **Detection:** segment intersection test; validator.
- **ShopPilot rule:** block with *"this shape crosses itself."* Offer Split at Intersections. (R002.)

### FM-04 Zero-length span
- **Trigger:** duplicate nodes on top of each other (node-edit or import artifact).
- **Mechanism:** parser produces a zero-length move — harmless or confusing, but signals broken geometry.
- **Worst case:** minor, but masks other issues; auto-fixable.
- **ShopPilot rule:** warning + one-click fix (Aspire's "fix zero length spans"). (R003.)

### FM-05 Toolpath outside stock bounds
- **Trigger:** vectors extend past material; or boundary/offset math wrong.
- **Mechanism:** tool rapids/cuts into empty space past the material edge; with soft limits off it just cuts air or hits the spoilboard edge.
- **Worst case:** cutting the wasteboard or fixture, spindle crash into clamps.
- **Detection:** toolpath vs stock rect intersection at calculation.
- **ShopPilot rule:** block or hard-warn; *"this cut goes off your material."* Highlight segments, offer Clip to Stock / Expand Stock. (R005.)

---

## B. Machining-strategy failures (tutors explicitly warn about)

### FM-06 V-Carve punch-through (wide gaps + no flat depth)
- **Trigger:** V-Carve over wide vectors (deep letters, wide borders) with no flat depth; 60° bit in thin material.
- **Mechanism:** depth is emergent = f(tool angle, vector width); wide opposing vectors push the V-bit deeper than material thickness.
- **Worst case:** bit through the bottom of the part, spoilboard damage.
- **Detection:** compute V-carve max depth from width×angle vs material thickness + flat depth setting.
- **ShopPilot rule (P0):** when `maxVDepth > materialThickness − startDepth` and flat depth unset → warn *"this carve can go through your material — set a flat depth."* (Directly from h7FccWQT2TA: "the distance between these two vectors will allow for your tool to go right through your material, so you're going to want to be careful of that, and you can control that with your flat depth.")

### FM-07 Part fly-out on last pass (no tabs, no vacuum)
- **Trigger:** profile cutout through material with no tabs and no vacuum hold-down.
- **Mechanism:** last pass severs the part; it shifts, spins, or flies; tool then cuts it again or the operator's hand is near.
- **Worst case:** ruined part, broken bit, injury.
- **Detection:** profile-through-material toolpath with zero tabs + machine profile has no vacuum → flag.
- **ShopPilot rule:** *"this part will be cut free with nothing holding it — add tabs or use hold-down."* Tab auto-placement default ON for through-cuts. (VAvj8KqOuE8: "this square is more than likely going to fly out of place on the last pass.")

### FM-08 Climb dig-in / climb-conventional misuse
- **Trigger:** climb milling on a gantry router with backlash; or wrong direction for material/machine.
- **Mechanism:** climb pulls the tool into the cut; with backlash the tool digs in, grabbing more material.
- **Worst case:** chatter, gouge, snapped bit.
- **Detection:** can't be fully detected in software; but can warn on climb + high backlash machine profiles, and always expose direction.
- **ShopPilot rule:** expose climb/conventional per toolpath (Vectric does; tutors say "run test cuts… if the finish looks better on the waste material, switch direction"). Consider a machine-profile "backlash" hint that warns on climb.

### FM-09 Wrong Z-zero / wrong datum (setup mismatch)
- **Trigger:** software says Z0 = material surface, operator zeros off the bed (or vice versa); or XY datum set bottom-left but operator picks a corner differently.
- **Mechanism:** whole job is offset in Z by material thickness → first pass cuts air or plunges 0.75" into the bed; XY shift cuts off the part.
- **Worst case:** bit into wasteboard, part ruined.
- **Detection:** none at generation — it's a setup contract.
- **ShopPilot rule:** make the material setup form mirror the machine (as Vectric does); surface a **pre-flight checklist** at job start and at save: "Z0 = material surface — set on machine before running." (Every getting-started video: "this is where we're going to set our tool… off the top of our material… just like I had told the software.")

### FM-10 Wrong material thickness (0.5" entered, 0.455" actual)
- **Trigger:** guessing thickness at job setup, not measuring; through-cut depth = entered thickness < actual.
- **Mechanism:** cutout doesn't fully sever (or cuts deeper than entered if reversed).
- **Worst case:** part won't come out; or tool hits spoilboard.
- **Detection:** none — operator measurement.
- **ShopPilot rule:** job setup prompt "verify thickness with calipers before toolpathing" (the clearance video literally re-measures: "it's actually a little bit thinner than a half inch, it's actually .455… always handy to have digital calipers around"). Show measured-vs-entered warning if a project file's thickness differs from the machine profile default.

### FM-11 Stale toolpath after vector edit (forgot recalc)
- **Trigger:** edit vectors (resize/move/offset) after calculating; then save/run without recalculating.
- **Mechanism:** G-code still reflects the old geometry.
- **Worst case:** cuts wrong size/position; may cut into neighboring features.
- **Detection:** dirty flag on toolpath vs source vector change (Vectric: explicit recalc selected/visible/all + success popup).
- **ShopPilot rule:** dirty badge + recalc required before save; block stale save. (WHFiP-5FMYU.)

### FM-12 Tool-change collision in single-file save
- **Trigger:** saving two toolpaths using different tools into one file when the post has no ATC.
- **Mechanism:** controller never gets M6; operator may not realize a tool change is expected mid-file.
- **Worst case:** runs second toolpath with wrong bit → broken bit/part.
- **Detection:** compare tool per toolpath vs post ATC capability at save.
- **ShopPilot rule:** exactly Vectric's error: *"visible toolpaths use different tools and the selected post processor does not support tool changing."* Offer split-to-multiple-files (ordered) or ATC post. (Txafg3oN8c0.)

### FM-13 Cutting off your own chamfer/feature (allowance offset)
- **Trigger:** profile cutout on the border line after chamfering the edge.
- **Mechanism:** cutout removes the chamfer (bit follows the vector line through the bevel).
- **Worst case:** beveled edge destroyed on final pass.
- **Detection:** none automatic in Vectric; the tutor works around by offsetting cutout by chamfer width.
- **ShopPilot rule:** when a profile-through cutout follows a chamfer toolpath on the same vector, warn: *"this cutout will remove the chamfer — offset it by the chamfer width."* (deMB2pc9-pY: "if we do that we're going to end up cutting off our chamfer… remember that 0.15.")

### FM-14 Ramp/plunge misuse (straight plunge stress)
- **Trigger:** deep first pass with no ramp on a rigid-but-slow machine or brittle material.
- **Mechanism:** vertical plunge loads the tool end; chatter/deflection; broken tip.
- **Worst case:** snapped bit mid-cut.
- **Detection:** pass depth > recommended (tool DB) with no ramp → suggest ramp.
- **ShopPilot rule:** warning when pass depth exceeds tool DB's safe pass depth and ramp disabled: *"consider a ramp plunge move to reduce tool stress."* (VAvj8KqOuE8: "rather than plunge the tool directly down the z-axis… quite strenuous on the tool.")

### FM-15 Over-aggressive feeds/speeds (chip load out of range)
- **Trigger:** feed rate too high for RPM×flutes (chip load too large) or too low (rubbing/heat).
- **Mechanism:** large chip load → chatter/deflection/snap; small → rubbing, burning, melted plastic.
- **Worst case:** broken bit; ruined part; melted acrylic welded to bit.
- **Detection:** compute chip load = feed/(RPM×flutes); compare to material range (BIT_FEEDS_LIBRARY.md §4).
- **ShopPilot rule:** warn out-of-range chip load at toolpath calc; show the computed chip load inline (educational + protective). Clamp feed to machine max rate ($110–$112).

---

## C. Machine-controller failures (from GRBL research — catch at run time)

### FM-16 Soft-limit violation
- **Trigger:** G-code target beyond $130–$132 max travel; jog beyond travel.
- **Mechanism:** GRBL: jog → `error:15` (no alarm); g-code motion → ALARM:2 (position retained, unlockable) or ALARM:1 hard limit (position lost).
- **ShopPilot rule:** pre-scan toolpath bounds vs machine travel before streaming (check mode `$C` idea); surface ALARM:1/2 distinctly: "re-home" vs "unlock".

### FM-17 Reset-while-motion (position lost)
- **Trigger:** ctrl-x or e-stop mid-cut.
- **Mechanism:** ALARM:3 — Grbl cannot guarantee position; lost steps likely.
- **ShopPilot rule:** after any reset during RUN → force "RE-HOME" banner; block job start until homed (unless user explicitly overrides). (AGENTS.md non-negotiable #3.)

### FM-18 Feed-rate starvation (start-stop motion)
- **Trigger:** send-response streaming with many short segments at high feed; planner buffer starves.
- **Mechanism:** cumulative serial lag → start-stop motion → scalloped finish, chatter.
- **ShopPilot rule:** implement character-counting streaming (GRBL wiki recommended-with-reservation) or pre-validate with `$C`; expose planner buffer `Bf:` when debugging.

### FM-19 Probe failure (workpiece touch-off)
- **Trigger:** G38.x probe cycle without contact, or probe state wrong.
- **Mechanism:** ALARM:4 (wrong initial state) or ALARM:5 (no contact in travel).
- **ShopPilot rule:** translate to plain language: "probe didn't touch — check wiring/depth."

### FM-20 Door/park interplay
- **Trigger:** safety door during run (or park enabled).
- **Mechanism:** DOOR state, spindle off; resume requires door closed + `~`.
- **ShopPilot rule:** show Door sub-state (0–3) and the resume path; never auto-resume on port reconnect.

---

## D. Preflight checklist (what ShopPilot should show before "Save / Start")

Consolidated from the 20 transcripts — every one of these was stated as a habit or failure:

1. Material setup matches the physical machine: **thickness (measured), XY datum, Z0 mode, rapid/plunge gaps clear clamps, home position safe**.
2. All selected vectors **closed**; validator clean (no overlaps/intersections/zero-spans) — auto-run on import.
3. Every toolpath **recalculated** after last edit (no dirty toolpaths).
4. Tool selected per toolpath; **feeds/speeds present** for material+machine (no grayed-out tools); chip load in range; feed ≤ machine max.
5. V-Carve: **flat depth set** or max emergent depth < material thickness.
6. Profile through-cut: **tabs present** or vacuum hold-down on machine profile.
7. Chamfer → cutout pairing: cutout **offset by chamfer width** if chamfer exists on same border.
8. Save: **post supports tool changes** or split files; file names encode cut order; output folder known.
9. Machine side: **homed**, Z zeroed on surface, datum set per setup form, controller alarm cleared.

## E. Preview warnings (what the 3D preview should flag visually)

- Highlight segments **outside stock bounds** (red).
- Highlight **open/duplicate/intersecting** vectors on selection (validator colors: Aspire uses pink duplicates, red overlaps).
- On V-Carve preview: show **max emergent depth** readout vs material thickness + flat-depth cap.
- On through-cuts: show **tabs** as visible bridges; if none and no vacuum, surface the fly-out warning banner.
- Show **chip load + feed vs machine max** in the toolpath summary line.
- Post-save: print an **operator sheet** (Vectric setup sheet analog): datum, Z0, tool list, order, safe gaps.

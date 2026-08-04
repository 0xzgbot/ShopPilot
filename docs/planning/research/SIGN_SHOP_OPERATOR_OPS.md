# Sign-Shop Operator Ops — forum proxy evidence + interview guide

**Date:** 2026-08-04 · **Method:** this pass has **no live interviews yet** — it provides (a) proxy evidence harvested from public CNC forums/communities, and (b) a ready-to-run interview guide for 5–10 real operators. Interviews are a human task (recruiting); the guide is the deliverable.
**Proxy sources:** Vectric transcripts (workflow habits), Carbide3D community, Onefinity forum, Avid CNC forum, Sienci forum, r/CNC, Shapeoko enthusiast guide, Facebook CNC groups (all public posts).

---

## 1. What proxy evidence already says (order of ops, zeroing, preview, naming)

### Order of ops (consistent across Vectric videos + community)
1. Set up job (size ≈ material, units, datum, Z0 mode).
2. Design/import; clean vectors.
3. **Check material setup** — the single most-repeated habit.
4. Create toolpaths (vcarve → clearance → drill → chamfer → cutout, grouped by tool).
5. **Preview in 3D** — "always best practice to preview your toolpath in 3D; if you see any problems, now is your time to correct it" (ooTRI9rHydw).
6. Save with correct post; **file name encodes cut order** (`welcome sign_1` = pocket, `_2` = cutout).
7. Machine: fixture (double-sided tape is the recurring example), set XY datum, **zero Z on material surface** (zero plate), run files in order.

### Zeroing — the #1 real-world failure theme [proxy evidence]
- r/CNC thread "Z zero on material or spoil board?": new users cut into the spoilboard because of Z-zero confusion.
- Onefinity forum: "Z axis shows 0 but is cutting into spoil board ~4 mm" — operator zeroed surface, software/model thought differently, or WCO drift.
- Sienci forum (Fusion): "tool path executes fine except boring into the spoil board. I am zeroing the Z axis off of the spoil board" — **mismatch between software's assumed Z0 and the physical zero**.
- Avid CNC: "Z axis zero changes while running a toolpath" — lost steps / loose wiring / brake, i.e. **hardware drift masquerading as software error**.
- **Takeaway for ShopPilot:** the Z0 contract must be displayed on the job setup, on the save sheet, and in the machine panel ("Z0 = material surface — set on machine"). Software cannot detect physical zero mismatch, but it can stop *silently assuming* it.

### Preview habits [proxy]
- Forum/community users cite preview for: checking pocket clearance into corners, confirming tabs, spotting through-cuts, and customer-facing renders (Vectric's material textures/surface colors are explicitly for "send off to a customer").
- Board-path preview / CAM preview is a named workflow in CNC groups — preview-before-cut is culturally expected, not optional.

### File naming / tool change [proxy]
- Carbide3D community: "split the file into two, dividing it at the point of tool change and saving the toolpaths as two separate files and running them one [after the other]" — file-per-tool is the universal habit.
- Vectric transcripts: multi-file save names `project_1, project_2…` in cut order; toolpath names appear in filenames and setup sheets.
- Shop implication: operators run **one file at a time, swapping bits between files**; the sender must make "next file" trivial and show the required tool per file.

---

## 2. Interview guide (5–10 sign-shop / small-shop operators)

Use for recruiting: local sign shops, CNC router groups (Facebook/r/CNC/forums), maker spaces, community college woodshops. Offer 15–20 min, structured below. Record feature *names* and *orders*, never proprietary files.

### A. Demographics & stack
1. What do you cut (signs, plaques, dimensional letters, 3D relief) and on what machine (make, controller: GRBL/FluidNC/other)?
2. Which design/CAM tools today (VCarve/Aspire, Carbide Create, Estlcam, Fusion, other)? Which do you *actually* use per job type?
3. Do you design in one tool and CAM in another? Where does the handoff happen (DXF/SVG/STL)?

### B. Order of operations (core)
4. Walk me through a typical job from order to finished part. Where do you spend most time?
5. When do you decide toolpaths (design first, or plan cutting while designing)?
6. Do you name files/toolpaths? What does the name tell you at the machine?

### C. Zeroing & setup
7. How do you zero X/Y and Z? Touch-off plate, paper method, visual? Off material surface or spoilboard?
8. Have you ever cut into the spoilboard? What happened and what did you change?
9. What do you check on the machine before starting a run?

### D. Preview & trust
10. Do you preview before cutting? What do you look for (depth, clearance, tabs, order)?
11. Have you caught a real mistake in preview? What was it?
12. What would make you trust software enough to skip a manual check?

### E. Failure stories (gold for FAILURE_MODE_LAB)
13. Tell me about a job that went wrong. What was the cause — geometry, feeds/speeds, zeroing, hold-down, tool?
14. What do you warn new operators about first?

### F. Feature wishlist (lean signal)
15. What's the ONE thing you wish your software did automatically?
16. What features do you never use (clutter to avoid)?

**Analysis plan:** cluster answers into (order-of-ops, zeroing ritual, preview habits, naming conventions, top failure causes, top wishlist). Merge findings into WHAT_IT_TAKES_CNC_APP.md and FAILURE_MODE_LAB.md. Target 5–10 operators; 3 is a minimum for signal.

---

## 3. Interim design implications (from proxy evidence alone)

1. **File-per-tool + ordered naming must be first-class** in the save flow and the sender's "next file" experience.
2. **Z0 contract everywhere**: job setup → save sheet → machine panel. Never let the software assume; always restate.
3. **Preview is the trust anchor** — it's culturally mandatory; invest in material fidelity + waste-removal (double-click) + per-path colors.
4. **Toolpath names leak into filenames and setup sheets** — make toolpath naming a visible, defaulted field.
5. **Setup sheet** (mucdprsJQkw analog) is what operators carry to the machine — datum, Z0, tool list, order, safe gaps.
6. Hardware drift (lost steps) is a real class of "Z changes mid-job" — machine panel should surface MPos/WPos and warn when WCO jumps unexpectedly.

# What it really takes to create a lean CNC / V-Carve / 3D carving app

> Research memo distilled from 67 Vectric (V12/V12.5) tutorial transcripts, fetched as captions only
> (no media downloaded). Source: `research/raw/vectric_yt_captions/`, catalog:
> `vectric_yt_catalog.csv`, per-video extractions: `extractions/`.
> Written for ShopPilot's lean bar (LEAN_CNC_SCOPE.md): offline Mac app, GRBL-class posts,
> V-Carve + clearance, 3D rough/finish, sheet-aware preview. Research evidence, not marketing.

---

## 1. Core workflow (from transcripts, not Aspire marketing)

Every Getting-Started video follows the same spine. Tutors repeat it so consistently it is the
product's skeleton:

1. **Job setup** — new file: single-sided, job size ≈ material size, units, Z-zero mode
   (material surface is the default and repeatedly stressed), XY datum (bottom-left is the
   tutorial default). Thickness entered, but *re-verified* later.
2. **Design / layout** — draw or import vectors (DXF), text, bitmap trace; offset, align,
   mirror, weld, node-edit to a clean set of **closed vectors**.
3. **Material setup re-check (mandatory gate)** — before ANY toolpath the software opens the
   material setup form: exact thickness (calipers!), datum, Z0, rapid-Z gap, plunge gap,
   home/start. Tutors call this "checking your material setup" in every single video.
4. **Toolpath creation** — pick strategy (pocket/profile/drill/V-Carve/3D), pick tool from DB
   (filtered by material + machine), set depths, **calculate**, then **preview in 3D**.
5. **Preview / simulate** — 3D preview of visible toolpath; double-click waste to remove it;
   per-toolpath colors; animated tool. This is where mistakes are caught *in software*.
6. **Save toolpaths** — choose machine + post processor (the dialect translator), choose
   grouping (one file vs multiple vs group-by-tool), save to known folder, take to machine.
7. **Machine setup mirrors software** — zero XY at the datum, zero Z on the surface, fixture
   (double-sided tape is the recurring example), then run the files in saved order.

**The through-line:** the software's job is to encode the machine contract (datum, Z0, safe
gaps, tooling, order) so the operator only has to *mirror* it on the machine. Every parameter
that appears in the toolpath form is a promise about the physical setup.

---

## 2. Must-have capabilities (ranked by mention + criticality)

Keyword pass over all 67 transcripts (full table: `LEAN_YT_FEATURE_MENTIONS.csv`). Ranked by
(mention count, criticality):

| # | Capability | Mentions | Why it's non-optional |
|---|---|---|---|
| 1 | Toolpath **preview / simulation** | 44 | The universal verification step. "Always best practice to preview your toolpath in 3D; if you see any problems, now is your time to correct it." |
| 2 | **Job/material setup** (size, thickness, datum, Z0, rapid/plunge gaps, home) | 22+22 | Mandatory gate before toolpaths; software forces it. The machine contract. |
| 3 | **V-Carve toolpath** (closed vectors, start/flat depth, V-bit, clearance) | 13 | The headline 2.5D feature; depth is emergent from tool angle + vector width. |
| 4 | **3D import + component/relief model** | 18+19 | STL/3D model import → heightfield is the 3D entry point. |
| 5 | **3D roughing + finishing toolpaths** | 7+9 | The 3D carving spine: boundary, allowance, strategy (Z-level/raster), stepover. |
| 6 | **Tool database** (geometry × per-material cutting data) | 14 | Feeds/speeds/pass depth/stepover come from here; per material+machine matrix. |
| 7 | **Save/export G-code via post processor** | 14+9 | The output contract; post = dialect translator; grouping rules respect tool changes. |
| 8 | **Profile toolpath** (multi-pass, tabs, ramp, side) | 15* | The cutout workhorse; tabs are the default safety for hold-down. |
| 9 | **Pocket toolpath** | 6* | Background removal; the V-Carve clearance tool is a pocket-like pass. |
| 10 | **Drill toolpath** (plunge at vector center) | 4* | Mounting holes; trivially simple but universally used. |
| 11 | **Recalculate (dirty toolpaths)** | 8 | Vector edits invalidate toolpaths; explicit recalc selected/visible/all. |
| 12 | **Vector editing**: offset, weld/subtract/overlap, join, node-edit, trim/extend, align/mirror/rotate | 5–21 | Design is a prerequisite for toolpaths; closed vectors are mandatory. |
| 13 | **Text tool + convert to curves** | 17 | Lettering is the core use case; convert-to-curves is the bridge to vectors. |
| 14 | **Vector validator** | 5 | Imports look fine but hide duplicates/opens/intersections that break toolpaths. |

\* profile/pocket/drill draw-tool mentions undercount because those features also appear inside
the multi-toolpath Getting-Started videos under the general "toolpath" keyword.

## 3. Small features tutors treat as non-optional

These look minor but appear in every workflow and are treated as table stakes:

- **`z=` shortcut** in cut-depth fields fills the material thickness — signals that
  "cut through material" is the most common intent, and that material thickness must be
  queryable from any toolpath form.
- **Closed-vector requirement** with a clear error ("there's no vector selected… you need to
  have a closed vector selected to do any v-carving") — enforcement, not just a warning.
- **Toolpath rename** — tutors rename every toolpath (pocket, cutout, vcarve, chamfer, drill);
  the name appears in the saved filename (`welcome sign_1` = pocket, `_2` = cutout) and in
  setup sheets. Names encode cut order.
- **Tabs** with auto-placement (constant count or spacing, "avoid corners and curved regions")
  and manual drag placement. Part fly-out on the last pass is the stated failure.
- **Ramp plunge moves** ("alleviate stress on the machine, prolong tool life") — on by
  default in many workflows; straight plunge is the anti-pattern.
- **Toolpath preview granularity**: selected vs all vs all-sides; per-toolpath color; draw
  tool to scale; animation speed slider; double-click waste to remove.
- **Material textures / solid colors / surface color** in preview — painting the material to
  match reality (customer-facing and finish-sanity checking).
- **Job templates** and **toolpath setup sheet** (mucdprsJQkw) — production hygiene; the setup
  sheet is what the operator carries to the machine.
- **Default post processor per machine** — "every time I open up this machine the G-Code
  inches post will be displayed first".
- **Multi-file save honoring toolpath order** — filenames numbered in run order
  (pocket=1, drill=2, profile=3…) with per-file tool info.

## 4. 3D carving path specifically

From the 3D roughing/finishing pair (5wOzzsZ870k, NF9oaCjXmAo) + Getting-Started 3D videos
(cORavE0W3fo, WzJOIdUfMO4):

1. **Model** — import STL/3D component or build relief; **modeling resolution** = pixel
   density of the heightfield ("very high" for real detail); model on the smallest sheet that
   fits it so pixels aren't wasted.
2. **Material setup with model position** — model thickness must be < material thickness;
   position model in material via gap-above/gap-below slider; keep a gap above for thickness
   variance unless cutting negative shapes (dishes/recesses) where the top must be bang-on the
   surface.
3. **3D roughing toolpath**:
   - Boundary: model boundary (default) / material / selected vectors / level, plus
     **boundary offset** ("cut outside the model boundary by the diameter of the cutter so the
     finish tool has room to fit").
   - **Machining allowance** left for the finish pass (0.04" example) — the explicit contract
     between rough and finish.
   - Strategy: **Z-level** (pocket layers at pass depth; optional profile-before/after each
     level for brittle materials; level-by-level vs depth-first order) or **3D raster**
     (follows the surface; avoid-machined-areas option; raster angle).
   - Ramp plunge option; vector selector for entry order.
4. **3D finishing toolpath**:
   - Ball-nose (1/8" example); boundary offset = finish-tool diameter (kills cusping at
     edges); same boundary source as roughing.
   - Strategy: **offset** (spiral inside-out) or **raster**; climb/conventional; **stepover**
     + optional **stepover retract** to hide witness marks.
   - **Rest machining**: add a smaller bit (1/16") with a minimum-detail slider — big bit for
     bulk, small bit for fine detail; per-tool strategy selectable.
   - Preview rough + finish results combined (subtract finish from rough) to verify the
     allowance was consumed.
5. **Optional fast path — sketch carving**: converts 3D content to a 2D V-Carve-like pass
   (line-thickness slider = detail) — cheap preview/prototype cut before committing to 3D.

Lean takeaway for ShopPilot: the *minimal* 3D spine is heightfield (modeling resolution),
rough (Z-level + allowance + boundary offset) and finish (ball-nose + stepover). Component
combine modes and base height are modeling conveniences; sculpt brushes, textures, and
multi-component trees are not required for the lean bar.

## 5. V-Carve path specifically

From h7FccWQT2TA (V-Carve toolpath), deMB2pc9-pY (clearance), kdvjB-4ET7o (sign):

1. **Vectors** — text to curves (nESYbpc9r6o) or imported; **closed vectors only**; weld
   overlaps; validate.
2. **V-Carve toolpath**:
   - **No cut-depth field** — depth is forced by the V-bit angle and the distance between
     opposing vector walls ("the software forces the V-bit as deep as it can until the side
     walls hit the two vectors"). Wide gaps → deeper cut → can punch through material.
   - **Start depth** = 0 at surface; raise it to carve *into* a pocket, or use it to fake
     bolder lettering (careful: letters converge).
   - **Flat depth** = cap on how deep the V goes (0.2" example) — the anti-punch-through and
     the "flat-bottom engraving" mode.
   - **Tool**: V-bit angle from tool DB (60° vs 90° shown — smaller angle = deeper cut for
     the same width); feeds/speeds per material+machine.
   - **Clearance tool** (P0 for ShopPilot): a separate end-mill pass (offset strategy) that
     pre-removes bulk material from wide/deep areas so the V-bit only sharpens the corners.
     Produces *two* toolpaths from one operation.
   - Vector start points / selection order / project-on-3D are advanced extras.
3. **Preview** — 3D preview; check the letter channels; compare tool angles.
4. **Cutout** — profile toolpath outside the border, cut through material, tabs, then the
   part drops out. Chamfer before cutout with an **allowance offset** equal to the chamfer
   width so the profile pass doesn't destroy the bevel.
5. **Save** — group V-Carve + chamfer (same V-bit) into one file to save a tool change;
   clearance, drill, cutout each their own file; run in saved order.

## 6. Common failure modes / preflight lessons (from gotcha content)

Top gotchas the tutors actually warn about (full list in per-video extractions):

1. **Open/duplicate/overlapping vectors** — look fine, silently break toolpaths. Validator is
   the fix; V-Carve mode ignores font-inherent intersections.
2. **Wrong/absent tool settings** — grayed-out tool = no feeds/speeds for this
   material+machine; forgetting = toolpath creation fails or runs unsafe feeds.
3. **Forgetting to recalculate** after vector edits — toolpath is stale (dirty-toolpath UX).
4. **Punch-through on wide V-Carve areas** — no flat depth, wide vectors, thin material.
5. **Zeroing off the wrong surface** — Z must be off the surface you carve into, not the bed.
6. **Material thickness lies** — "always handy to have digital calipers"; 0.5 vs 0.455 in the
   clearance video; thickness drives cutout depth and toolpath preview fidelity.
7. **Cutting off your own chamfer/feature** — profile cutout on the vector line destroys the
   chamfer; allowance offset = chamfer width.
8. **Part fly-out on last pass** — no tabs / no vacuum hold-down.
9. **Model depth > material thickness** — software warns; must resolve before toolpathing.
10. **Mixing tools in a single-file save** — "visible toolpaths use different tools and the
    selected post processor does not support tool changing" → split files or use an
    ATC-capable post.
11. **Toolpath order ≠ cut order** — save order is respected by multi-file save; filenames
    encode it; reorder toolpaths by dragging before saving.
12. **Preview discipline** — "it's always best practice to preview your toolpath in 3D; if
    you see any problems at this point, now is your time to correct it" — stated in nearly
    every video.

## 7. Explicit non-goals inferred from fluff we skipped

Wave-1 selection deliberately excluded (catalog `skip_reason` column + LEAN_CNC_SCOPE.md):

- **Laser** (incl. hybrid CNC-laser projects) — separate module, excluded.
- **PhotoVCarve / lithophane** — photo-2-relief is excluded from lean.
- **Rotary / wrapped / two-sided** — post-lean (Track 5 in FINISH_ROADMAP).
- **Cabinet import / nesting / plate production / AMM (Advanced Machining Module)** — kitchen/
  production territory.
- **Design & Make model shop, clip art, FREE CNC Projects, In the Labs** — content marketing,
  not capability evidence (we used them for workflow only, never assets).
- **Online tool database / machine search / cloud posts** — ShopPilot is offline by design;
  the *concepts* (machine→post mapping, default post) stay, the cloud transport goes.
- **Sculpt brushes / texture painting / turn-and-spin / extrude-weave** — Aspire modeling
  luxury, not lean 3D carving.
- **EasyCarve/EasyCreate** — consumer line; teaches nothing about CAM internals beyond what
  the full videos cover (we still cataloged their setup videos for the machine/material/tool
  DB model, which is cleanly explained there).

## 8. Blind spots vs ShopPilot (UNVERIFIED against codebase)

This memo is transcript evidence only; mapping to ShopPilot's current state is NOT verified
against MASTER_KANBAN/Sources in this pass (research card scope). Candidate blind spots a
follow-up should check:

- **Dirty/recalc UX** — Vectric makes recalc explicit and granular (selected/visible/all) with
  confirmation; ShopPilot's dirty-flag design should match this contract.
- **Preview material fidelity** — Vectric's preview is a deliverable (textures, surface
  color, per-path colors, animated tool, waste removal). ShopPilot's sheet-aware preview
  (SPK-1103) is the right investment; consider per-toolpath color and waste click-to-remove.
- **Job templates + toolpath setup sheet** — small but repeatedly featured; cheap wins.
- **Vector validator** — Vectric treats import validation as a first-class tool with
  auto-fix (zero-length spans) and toolpath-type-aware rules (V-Carve mode). ShopPilot has no
  equivalent in the lean list; SVG/DXF import will need it.
- **Model-in-material positioning** (gap above/below) — a distinct 3D concept from Z-zero;
  make sure the heightfield pipeline exposes it.
- **Boundary offset + machining allowance** — the rough↔finish contract; goldens should pin
  these semantics.
- **Tool geometry vs cutting-data split** — ShopPilot's tool DB (P1) should store per-material
  feeds/speeds under one tool, not one tool per material.

*Marked UNVERIFIED — needs a codebase pass against MASTER_KANBAN before acting.*

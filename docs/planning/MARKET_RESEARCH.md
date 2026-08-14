# Competitor baseline: honest ingestion status + market complaint research

**Date:** 2026-07-28  
**Purpose:** Correct the record on how thoroughly the reference vendor's docs were studied, and capture **external** market pain (forums, Reddit, Mac CNC communities, product reviews) so ShopPilot can beat the incumbent on *experience*, not only feature count.

---

## Part 1 — Did we ingest the entire reference vendor FAQ / User Guide?

### Short answer

**No — not line-by-line every page.**  
**Yes — we used the full site map / User Guide TOC as a capability inventory and deep-read the core workflow + 3D system + V12 what’s-new.**

Calling the previous work “obsessive full FAQ ingestion” would be **overstated**. Treating it as a **solid structural baseline with known gaps** is accurate.

### What “the FAQ” actually is

The vendor’s surface is several things people mix up:

| Source | What it is | Our coverage |
| --- | --- | --- |
| User Guide hub (public reference docs) | Chapters 01–15 (workflow, 2D, 3D, rotary, posts) | **Read in depth** (including composite/combine modes, rotary origins, post-processor structure outline) |
| Reference manual / **form pages** | One page per tool (Profile form, Nest Parts, every strategy…) | **Catalogued from TOC** (~150+ entries); **not** every form field-by-field |
| What’s New V12 (public reference docs) | V12 UI + new tools | **Read** |
| Vendor support FAQs (public site) | Licensing, Mac, installs | **Sampled** (especially Mac) |
| Single-page dump | Mega HTML of help | **Not fully walked end-to-end** |

### What we *did* capture well

- Full product **module map** (Getting Started → Interface → Design → Layers → Clipart → 3D tools → Toolpaths → Tooling/Posts → Gadgets → Laser → Menus).
- **Workflow logic** the vendor teaches: job structure, vectors vs bitmaps, toolpath independence from art + explicit recalculate, preview = trust model, post = translation.
- **3D architecture**: Components, Levels, combine modes (Add/Subtract/Merge/Low/Multiply), mirror modes, multi-sided view.
- **Strategy list** at product level (Profile through Laser Picture, V12 Sketch Carving, VCarve Inlay, Keep-outs).
- File types and job types (single / double / rotary).

### Corners that were cut (explicit)

1. **Not every strategy form** — e.g. every Profile ramp option, every Pocket clearance algorithm toggle, every 3D finish stepover pattern was **not** transcribed field-by-field.
2. **Not every Gadget / post block** — Post Studio was outlined, not a full POST language re-spec.
3. **Not every keyboard shortcut / right-click menu leaf**.
4. **No CRV format reverse-engineering** (correct legally; means import parity is open research).
5. **Assumptions** in the product plan (stage rail, recipes, Metal heightfield) are **product design**, not claims that the reference already works that way.

### Baseline integrity rule (going forward)

| Rule | Practice |
| --- | --- |
| **TOC = inventory** | Every form link in the reference docs nav gets a row in `FEATURE_PARITY_MATRIX.md` |
| **Form = acceptance criteria** | Before shipping a strategy, engineer opens **that** reference form page and maps **every control** to ours or documents intentional omission |
| **No “probably has X”** | If not on TOC and not verified, mark `UNVERIFIED` |
| **Ingestion waves** | Sprints that only *read + matrix-update*, no code — one toolpath family per week |

### Recommended completion of baseline (team task)

- [ ] **DOC-01** Crawl all reference form URLs → CSV (name, category, URL).
- [ ] **DOC-02** For each strategy, capture: required vectors, tools, material deps, outputs, known error strings (“Ignoring unsuitable open vectors”, etc.).
- [ ] **DOC-03** Diff V12 → V12.5 release notes when available; update matrix.
- [ ] **DOC-04** Pair with hardware lab: recreate reference tutorial projects as golden jobs.

Until DOC-01–02 finish, **feature completeness claims should say “capability parity from TOC + deep workflow study,” not “byte-perfect FAQ clone.”**

---

## Part 2 — Market research: what people complain about

Sources include the vendor’s own Mac FAQ stance, Onefinity/Sienci/Carbide forums, Reddit r/CNC & r/hobbycnc, product comparison articles, YouTube Mac/VM discussions, and public upgrade pricing discussions. The incumbent is **widely liked** for 2.5D/artistic CNC; complaints cluster in predictable places. We turn each into a **ShopPilot fix**.

### Complaint cluster 1 — “It doesn’t run on Mac (natively)”

**What people say**

- The vendor’s FAQ: products need **modern Windows**; Mac is via **Parallels/VM**, with **limited support** for that setup.
- Ongoing community content is literally *“How to run the incumbent on macOS”* (Parallels / VMware), not “download the Mac build.”
- Public reports of **VM-specific pain**: dialog crashes on hover/click, **3D view / simulation going black**, version lag until the vendor patches VM issues (e.g. 12.006 called out as fixing Mac VM crashes).
- Sienci and others: “shame there’s no MacOS version”; graphics people live on Mac, CNC software doesn’t.
- Social: direct asks to the vendor “what’s stopping a Mac version?”

**Why it hurts**

- Extra cost (Windows license + Parallels).
- Extra failure modes (GPU black screen, UI scaling, file path friction).
- Feels second-class for designers who already own Macs.

**How ShopPilot alleviates (easy wins)**

| Fix | Difficulty | Impact |
| --- | --- | --- |
| **Native Apple Silicon SwiftUI app** | Core product | Category-defining |
| **Metal 3D view** (native Mac) | Core | Stable 3D rendering |
| **No VM in the critical path** for serial + files | Core | Reliability |
| Marketing: “Mac-native CNC studio” | Low | Captures entire abandoned segment |

---

### Complaint cluster 2 — Price / upgrade ladder / “The incumbent is overkill”

**What people say**

- The incumbent is repeatedly called **very expensive** / overkill for simple work; the mid-tier is often recommended first.
- Upgrading from mid-tier to top-tier historically cited around **~$1,300 difference** (full suite ~$2k class); annual major upgrades hundreds of dollars for some users.
- Hobbyists ask “how do I afford the incumbent?”; many stay on Carbide Create / Fusion free tiers longer than they want.
- Laser features as **paid add-on module** (docs: not included by default) — extra purchase friction.

**Why it hurts**

- High **commitment tax** before you know if 3D modeling tools are needed.
- Feature **gated by SKU** (Desktop vs Pro vs top-tier vs Laser module) creates resentment and decision paralysis.

**How ShopPilot alleviates**

| Fix | Difficulty | Impact |
| --- | --- | --- |
| **One app, progressive unlock** (usage-based or tiers that don’t reinstall) | Product | Less ladder anxiety |
| **Free/cheap “Control + Profile/Pocket” tier** → Studio 3D paid | Product | Match real journeys |
| **Laser included or clear modular store** without second “module mystery” | Medium | Transparency |
| **No forced annual upgrade** for security/compatibility if using evergreen model | Business | Trust |
| Honest: *don’t race to $0* — race to **fair value for Mac-native + machine** | Strategy | Differentiation |

---

### Complaint cluster 3 — Not parametric / weak “real CAD”

**What people say**

- Reddit: frustration that incumbent CAM tools lack **fully parametric** design — change a dimension and have features/toolpaths update intelligently.
- Comparisons: CAD score lower than Fusion; “horrible at modeling” for full 3D CAD, strong at **2D geometry + fast NC** and **relief**.
- Users bounce Fusion ↔ the vendor’s suite: Fusion for parametric assemblies, the vendor’s suite for **signs / V-carve / relief speed**.

**Why it hurts**

- Production shops rework jobs (cabinet families, parametric plaques) painfully.
- Guitar / mechanical parts often leave the vendor’s suite for Fusion.

**How ShopPilot alleviates**

| Fix | Difficulty | Impact |
| --- | --- | --- |
| **Document variables + driven dimensions** on vectors (Phase 1 parametric-lite) | Medium | Hits top Reddit pain without full CAD |
| **“Linked toolpath” option** (opt-in auto-recalc when source art changes) — default **off** to keep the incumbent’s safety model | Medium | Best of both |
| **Import STEP/Fusion timeline later**; don’t pretend to be SolidWorks in year 1 | High later | Honesty |
| **Recipes for plaques/signs** with width/height variables | Low | 80% of hobby parametric need |

---

### Complaint cluster 4 — UI density / workflow thrash / learning shape

**What people say**

- The vendor’s suite is praised as **easier than Fusion for CNC routers**, but still has **large tool matrices**, design-left / toolpath-right thrash, and many tools never used in a given job.
- V12 explicitly modernized UI (unified panels, DPI, orthographic, view toolbar) — evidence the vendor **knows** density was a problem.
- Beginners hit opaque messages (“Ignoring unsuitable open vectors”) and need tribal knowledge (join vectors, closed shapes for V-carve).
- Design-in-vendor-suite vs design-elsewhere: “not ideal for pure design work.”

**Why it hurts**

- Cognitive load; fear of “wrong button.”
- Time lost switching views and finding tools.

**How ShopPilot alleviates**

| Fix | Difficulty | Impact |
| --- | --- | --- |
| **Stage rail + ≤12 primary tools** (already in UX plan) | Medium | Clarity |
| **⌘K command palette** with plain-English synonyms | Low–Med | Discovery |
| **Preflight doctor**: open vectors, tiny segments, self-intersections **before** Calculate | Medium | Replace cryptic errors with fixes |
| **Context coach** with one-tap “Close gaps / Join within 0.1mm” | Medium | Support cost ↓ |
| **Job recipes** for calibration, signs, inlays | Low | Time-to-first-success |

---

### Complaint cluster 5 — Preview / simulation is slow; iteration loop hurts

**What people say**

- Entire tip economy around **slow toolpath previews** — use Standard quality first, Maximum only at end; cancel and restart after mistakes.
- Complex jobs + slow machines = painful wait loops.
- Preview speed/quality tradeoffs are user-managed folklore, not elegant product design.

**Why it hurts**

- Iteration is the job; waiting kills flow.

**How ShopPilot alleviates**

| Fix | Difficulty | Impact |
| --- | --- | --- |
| **Progressive preview** (fast coarse → refine idle) | Medium | Feels instant |
| **Dirty region sim** (only re-sim changed toolpaths) | High | Big win |
| **Background Metal compute** + never freeze UI | Medium | Modern expectation |
| **“Draft / Final”** explicit modes with default Draft | Low | Same as tips, productized |
| **Instant toolpath wire display** before full material sim | Low | Trust without wait |

---

### Complaint cluster 6 — Toolpath ↔ art disconnect and recalc friction

**What people say / product design**

- The vendor **deliberately** does not auto-update toolpaths when art moves (safety/predictability). Users who don’t know that get **wrong cuts** or confusion (“I moved the text, why didn’t the path move?”).
- “Recalculate all” on large jobs is a chore; V12.5 messaging around **visualizing when toolpaths need calculation** shows ongoing pain.

**How ShopPilot alleviates**

| Fix | Difficulty | Impact |
| --- | --- | --- |
| **Bright dirty badges** on toolpath list + export blocked until resolve | Low | Safety + clarity |
| **One-click recalc this / all dirty** | Low | |
| **Optional link mode** per toolpath (“Follow source”) | Medium | Power users |
| **Diff preview** (ghost old vs new path) | Medium | Confidence |

---

### Complaint cluster 7 — Machine handoff is fragmented

**What people say**

- The incumbent handles design; **controller software** (Carbide Motion, UGS, machine proprietary) runs the cut. File extension / post mismatches (“.gcode vs .nc”) confuse beginners.
- Mac users juggle **the incumbent in a VM + host serial** awkwardly.
- Separate transfer utilities (VTransfer-class) are another hop.

**How ShopPilot alleviates**

| Fix | Difficulty | Impact |
| --- | --- | --- |
| **Machine stage in same app** (ShopPilot Control) | In plan | Huge differentiator |
| **Post auto-selected from machine profile** | Low | Fewer wrong posts |
| **Pre-flight checklist** (air cut, zero, tool, hold-down) from the vendor’s own run guide | Low | Fewer ruined boards |
| **One-click Run** after Preview OK | Medium | |

---

### Complaint cluster 8 — 3D modeling is “relief CAD,” not full CAD — and the SKU gap stings

**What people say**

- The incumbent’s 3D is excellent for **artistic relief / collage components**, not Rhino/Fusion solids.
- Paying top-tier premium **only for 3D creation** while the mid-tier can *import* 3D frustrates users who need one modeling feature.
- Component combine modes / levels are powerful but **abstract** for new 3D users.

**How ShopPilot alleviates**

| Fix | Difficulty | Impact |
| --- | --- | --- |
| **Visual combine-mode previews** (live dome+square style teaching) | Medium | Learning |
| **“3D starter” shapes with interactive handles** (V12 direction — lean harder) | Medium | |
| **Import-first 3D path free**, authoring tools clearly labeled | Product | Fair packaging |
| **Don’t overclaim solid CAD** | Strategy | Trust |

---

### Complaint cluster 9 — Ecosystem lock-in / gadgets / Lua

**What people say**

- Gadgets in Lua; users ask if V12 still Lua-only and want more API power.
- Clipart / portal ecosystem is great *if* you’re bought in; otherwise lock-in feel.

**How ShopPilot alleviates**

| Fix | Difficulty | Impact |
| --- | --- | --- |
| **First-party recipes** (JSON) before arbitrary scripts | Low | Safety |
| **Open import/export** first-class | Low | Anti-lock-in |
| **Optional plugin API** later with sandbox | High | Power users |

---

### Complaint cluster 10 — What people *don’t* complain about (don’t “fix”)

Protect these strengths:

| Strength | Implication for ShopPilot |
| --- | --- |
| **Fast path to good router G-code** for signs/cabinetry | Don’t bury Profile/V-Carve |
| **Excellent tutorial / community culture** | Invest in coach + sample jobs early |
| **Predictable toolpaths** (no silent rewrite) | Keep explicit calculate by default |
| **One-time license culture** (vs pure subscription hate for other CAD) | Be careful with pricing model messaging |
| **Purpose-built for 3-axis CNC routers** | Stay focused; 5-axis is not the wedge |

---

## Part 3 — Prioritized “beat the incumbent” backlog (from market pain)

Scored for **user pain × ease of differentiation** (not full CAM math hardness).

| Rank | Initiative | Attacks cluster | Effort |
| --- | --- | --- | --- |
| 1 | **Native Mac app** | 1 | Product foundation |
| 2 | **Integrated Machine stage** | 7 | Medium (already planned) |
| 3 | **Preflight vector doctor + plain errors** | 4 | Medium |
| 4 | **Progressive / regional preview** | 5 | Medium–High |
| 5 | **Dirty toolpath UX + optional link** | 6 | Low–Medium |
| 6 | **Stage rail + ⌘K + recipes** | 4 | Medium |
| 7 | **Variables / parametric-lite dimensions** | 3 | Medium |
| 8 | **Fair modular pricing (not $2k wall)** | 2 | Business |
| 9 | **Visual 3D combine teaching** | 8 | Medium |
| 10 | **Field-level parity from DOC crawl** | Completeness | Ongoing |

---

## Part 4 — Research gaps (do next)

Market research above is **real but not exhaustive**. Next passes:

1. **Vendor forum** “Wish List” / top-tier subforums — top 50 wishlist threads (need manual browse; search engines under-index).
2. **Facebook CNC groups** Mac + vendor threads (qualitative).
3. **Support ticket patterns** if any public; YouTube comments on official tutorials.
4. **Win-loss interviews** (5 incumbent users, 5 Mac CNC users on Fusion/Carbide).
5. **Structured survey** after alpha: “What made you leave / avoid the incumbent?”

---

## Part 5 — Updates to planning doctrine

1. **Baseline = TOC inventory + form-level AC**, not “we read the FAQ once.”  
2. **Parity matrix** tracks *reference capability*; **pain matrix** (this doc) tracks *why users leave*.  
3. Shipping order should **interleave** pain wins (Mac native, machine, preflight, preview) with **capability** (V-carve, 3D) — not capability-only.

---

## Summary for stakeholders

| Question | Answer |
| --- | --- |
| Did we ingest the entire FAQ? | **No.** Full **TOC/capability map** + deep **workflow/3D/V12** study; **not** every form field. |
| Is the feature plan still valid? | **Yes as inventory**, with **DOC-01/02** required before “complete parity” claims. |
| Where do we win easiest? | **Native Mac**, **machine in-app**, **faster iteration (preview/dirty UX)**, **clearer errors**, **fair packaging**, **parametric-lite**. |
| Where must we still match the incumbent? | Toolpath quality, V-carve/inlay family, relief modeling depth, posts. |

*Being honest about ingestion is how we get better than the incumbent — not by claiming we already are.*

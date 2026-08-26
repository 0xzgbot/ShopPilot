# Market gaps 2026-08-21 — what people still ask CNC apps for

**Purpose:** Polish the ShopPilot feature bar against current competitors and *repeated* operator complaints — not a the incumbent form-field crawl.

**Method:** Public forums (Carbide, Sienci, V1E, LightBurn, Sawmill Creek, the incumbent FAQ), 2026 comparison writeups, and **YouTube captions ingested this pass** (no video files stored). VectorPilot has **no extra market corpus**; this is ShopPilot research.

**Captions ingested (auto-subs):**

| ID | Title | Why it matters |
| --- | --- | --- |
| [GgeP3nUztpw](https://www.youtube.com/watch?v=GgeP3nUztpw) | 2026 CNC Design Software Review (Scott / Sienci-adjacent) | Explicit CAD vs CAM vs **sender** split; Easel/Carbide/Carveco/Fusion/Onshape/gSender ladder |
| [xLPVwGWA8vw](https://www.youtube.com/watch?v=xLPVwGWA8vw) | the incumbent UGM 2025 (Edward) | Spark for Mac = **entry** product + their machine-transfer utility GRBL; V13 assembly view; their simplified carve product AI/credits; core still Windows |
| [xF3AE03t6jI](https://www.youtube.com/watch?v=xF3AE03t6jI) | gSender full beginner tutorial (IDC Woodcraft) | 16k+ words because **control is a second career**; probe plates, macros, spoilboard surfacer **inside the sender** |
| [IvrXHz2xDUo](https://www.youtube.com/watch?v=IvrXHz2xDUo) | Fusion vs V-carve V-inlay cutting boards | Fusion is free + photoreal; **terrible vector CAM**; V-carve wins join/close/inlay speed |
| [ntFIv-N2rS8](https://www.youtube.com/watch?v=ntFIv-N2rS8) | MillMage official trailer | Dogbones / T-bones, rest pockets, **trochoidal slotting**, custom G-code (not post language), toggle-ops re-run |
| [HR9gBi7TEkY](https://www.youtube.com/watch?v=HR9gBi7TEkY) | MillMage PSA vs Easel | Switch from ~$24/mo Easel (~$600 spent) to ~$149 perpetual intro |
| [vTL6wVD21zk](https://www.youtube.com/watch?v=vTL6wVD21zk) | MillMage vs V-carve welcome sign | LightBurn-shaped design + material wizard vs the incumbent |
| [I1EhAPNXdzQ](https://www.youtube.com/watch?v=I1EhAPNXdzQ) | Auto touch plate | V-bit **tip** probe; tool-change = **Z only** (do not re-XYZ); alarm 1/2 folklore |
| [Q3juIm79uh0](https://www.youtube.com/watch?v=Q3juIm79uh0) | XYZ probe in CNCjs | Built-in probe is Z-only; XYZ is a **vendor macro** |

Prior corpus (still valid): 67 the incumbent tutorial captions in `extractions/`, `WHAT_IT_TAKES_CNC_APP.md`, `MARKET_RESEARCH.md` Parts 1–5, `USER_WISHLIST_SUMMARY.md`.

---

## 1. Competitive snapshot (router hobby / sign / 2.5D)

| Product | Native Mac | Design+CAM | GRBL send in-app | V-carve quality | 3D relief | Nest | Honest price |
| --- | --- | --- | --- | --- | --- | --- | --- |
| the incumbent V-carve / the incumbent suite | No (Parallels). Spark = separate entry app | Yes | No (their machine-transfer utility / USB) | Best-in-class | the incumbent suite / Pro 3D | Yes (Pro) | $349–~$2k + upgrades |
| the incumbent's Mac entry product | Yes (new) | Entry 2D | Yes (their machine-transfer utility built in) | Basic | Not the full 3D suite | Unknown/limited | Entry SKU |
| Fusion 360 | Yes | CAD-first CAM | No | Awkward / plugins | Best solids / metal | Weak for sheet goods | Free personal / sub |
| Carbide Create + Motion | Yes | Simple CAM | Separate Motion | Inlay “fudge factor” folklore | Pro / slow calc | Limited | Free / Pro lock on G-code+STL |
| Estlcam | Windows | Fast 2.5D | Some firmwares | Weak vs the incumbent | Weak | Simple | ~€49 perpetual |
| MillMage | macOS via **Rosetta** (ARM promised 1.0) | Yes | **Yes** GRBL/Smoothie | 0.9 Pro | 0.9 Pro | 0.9 Pro | $99 / $199 |
| gSender / UGS | Electron / multi | **No CAM** | Yes (best GRBL UI) | n/a | n/a | n/a | Free |
| Carveco | Windows | Yes | No | Strong | Image-to-relief / AI | Yes (tier) | Sub / perpetual |
| **ShopPilot** | **Yes Apple Silicon** | Yes | **Yes** (sim + serial) | Lean (clearance P0) | Heightfield rough/finish + lithophane + I2R | **1900f shipped** | OSS / personal |

**2026 market move:** LightBurn’s MillMage and the incumbent's Mac entry product both attack the **same wedge ShopPilot already claimed** (Mac + less Windows tax + some send). Spark is **not** full V-carve. MillMage is the paid product to beat on UX of CAM+control.

---

## 2. What people constantly ask that still is not delivered well

Ranked by **how often it shows up** × **how badly incumbents still fail**. These are not “more combo-box strategies.”

### 1. Stop making me run three programs (CAD / CAM / sender)

Scott’s 2026 video still **defines the market as three apps**. Garrett’s gSender video is an entire course because after V-carve/Fusion you still must learn DRO, unlock alarms, jog, probe, macros, start/pause.

The incumbent's own UGM pitch for Spark: “completely self-contained… design all the way through to machining” — they know the split is the beginner killer.

**ShopPilot:** Machine stage exists. Gap is **gSender-class probing, M6 tool-length, spoilboard surfacer, alarm decode** — not another pocket strategy.

### 2. Probe + tool change that does not crash Z or skip the first M6

Sienci GitHub #803, SLB forum, Carbide “BitSetter always off by 3 mm”: Fusion posts emit a leading M6; senders double-probe; `$13` unit bugs; G28 vs soft limits.

**Still tribal:** macros, “ignore first tool call,” cancel the wizard and hit Resume.

**ShopPilot:** Productize **XYZ probe plate + optional fixed tool sensor** with the **same** session as CAM (tool diameter from the job, skip first M6 when the bit is already in).

### 3. V-inlay that actually fits

Carbide Create threads 2025–26: plug/pocket numbers that **do not change fit**; V-bits with **flat tips** vs software assuming a sharp point; runout; “fudge factor.” Fusion inlay video: test-cut, cut in half, glue moisture cupping, press.

**Ask:** inlay wizard with **tip diameter, glue gap, compression fudge, male/female paired toolpaths**, not three unlabeled depth fields.

**ShopPilot:** Inlay recipes exist on the PC port; Mac needs the **honest physics UI**, not more V-carve variants.

### 4. Vector doctor (Fusion users are screaming)

Inlay video: V-carve wins because it **rounds corners, adds boundaries, finds zero-span / overlaps**. Fusion is “terrible for editing vectors.”

ShopPilot already has `import_torture/` + validator research. The undelivered part is **first-class Design-stage doctor with one-tap join/close** (preflight copy, not a silent ignore).

### 5. Feeds for *this* hobby router, not a Haas

Grayed-out tools until machine+material cutting data exists (the incumbent model). Forums still share 40–60 ipm folklore. Nobody wants Fusion’s industrial adaptive defaults on a Shapeoko.

**ShopPilot:** `BIT_FEEDS_LIBRARY.md` + `TOOL_DB_SEED_SPEC.md` are written. **Wire seed → recalc → chip-load warning (FM-15)** is the gap.

### 6. Rest machining that does not recut the whole pocket

Carbide: rest + Advanced V-carve not combined; Fusion rest diameter folklore. Rest is the difference between a 1/4" then 1/16" job and a snapped 1/16".

VectorPilot already has rest-rough in heightfield. Mac should **surface it** on pocket / V-clearance / 3D rough.

### 7. Spoilboard surfacer and “first job” generators in the control app

gSender Tools tab: surface, rotary surface, XY square — **no CAM install**. Beginners ruin the first sign because they never faced the bed.

**ShopPilot:** Machine-stage recipe: surface spoilboard G-code from sheet size + bit.

### 8. Photoreal “sell the job” vs honest cut sim

Fusion wins customer mockups (colored woods). V-carve preview is trusted for **cut geometry**, not marketing renders.

**ShopPilot:** Keep honest heightfield sim. Do **not** chase Fusion rendering. Optional: per-layer material color in preview (already in wishlist as surface-color).

### 9. Native Mac that is not a toy SKU

UGM + FAQ: core the incumbent remains Windows; Spark is introductory + GRBL. Parallels threads still active in 2026. MillMage still Rosetta.

**ShopPilot already wins this** if quality holds. Marketing should say: Spark = training wheels; ShopPilot = full lean CAM + control on Apple Silicon.

### 10. Lock-in (C2D / cloud / SKU walls)

Carbide free: no G-code export (C2D + Motion). Easel: no offline. The incumbent: Desktop job-size + 3D gated. Carveco AI: subscription. EasyCreate: **credits**.

**ShopPilot:** Open `.shoppilot` + GRBL files. Do not add credit meters.

---

## 3. What people do *not* actually want (don’t build)

| Noise | Why skip |
| --- | --- |
| AI prompt-to-relief / EasyCreate credits | Incumbent **upsell**. ShopPilot Image-to-Relief is the honest substitute. |
| V13 “assembly view” for flat-pack | Real, but furniture CAD. Post-lean. |
| 964 posts / Mastercam / 5-axis | Wrong machine class. |
| In-app YouTube / cloud clipart | LEAN_CNC_SCOPE non-goal. |
| Laser / LightBurn chase | Held. MillMage exists for people who want LightBurn’s CNC. |
| Being SolidWorks | 2026 review: Fusion/Onshape for parametric furniture; V-carve for signs. Stay V-carve-shaped. |

---

## 4. ShopPilot vs the gap (after Phase S)

| Gap | ShopPilot now | Next thin slice |
| --- | --- | --- |
| Mac native | Shipped | Keep ARM; MillMage still Rosetta |
| CAM + send | Shipped (frame/jog 1900b, dock 1900d) | Probe + M6 TLS wizard |
| Photo / lithophane / I2R / nest / beginner | 1900a–f | Harden, don’t expand SKUs |
| V-carve clearance | Lean P0 | Inlay fudge + tip radius |
| Tool DB feeds | Spec exists | Seed JSON + gray-out + chip-load preflight |
| Vector doctor | Fixtures exist | Design UI one-tap repair |
| Rest machining | Engine on PC; Mac 3D rough | Pocket/V-clearance rest UX |
| Spoilboard surface | Missing | Machine-stage generator |
| OSS license | 1900g hold | Owner MIT vs Apache |

---

## 5. Recommended order (pain × differentiation, not parity tourism)

1. **Probe XYZ + tool-length / skip-first-M6** (attacks the sender gap MillMage/gSender own).
2. **Tool DB seed wired to toolpaths + chip-load warning**.
3. **Vector doctor in Design** (Fusion’s wound, V-carve’s moat).
4. **V-inlay physics** (Carbide’s open wound).
5. **Spoilboard surfacer** in Machine (gSender copy, 1 card).
6. **Rest machining UX** on pocket / V-clearance.
7. License + README honesty (1900g).

Do **not** reopen dual-side/rotary/laser/Post Studio for this wave.

---

## 6. Source notes

- Scott 2026: “the only wrong software is the one that makes you rage quit”; beginner = Easel/Carbide; signs = Carveco; parametric = Fusion/Onshape; **his personal two: V-carve + Onshape**; sender = gSender.
- the incumbent UGM: Spark native Mac **entry**; their machine-transfer utility for GRBL/grblHAL (FoxAlien, SainSmart, Sienci-class); V13 assembly; their simplified carve product V-text + layouts; **core Windows**.
- gSender tutorial: CAD → CAM → G-code → **then** sender; probe puck vs corner plate vs autozero (V-bit cannot use square-step XY math); macros for bit change park; surfacing **in control**.
- Fusion inlay: Z0 on spoilboard vs surface; vector hygiene; Fusion photoreal vs V-carve vector CAM.
- MillMage 0.9 forum: V-carve clearance-bit “linked operations” still in progress (same gap as everyone).
- Carbide: inlay fit + finish-path calc time (V8 vs V7).
- MillMage trailer (second caption batch): dogbones/T-bones, rest pockets, trochoidal slots for floppy hobby machines, re-run one op without re-posting. Easel refugees cite subscription burn. CNCjs/gSender probe: XYZ is still a macro; tool-change must not re-zero XY.

*This pass is qualitative frequency, not a counted survey. Win-loss interviews still blocked (`INTERVIEW_PACK.md`).*

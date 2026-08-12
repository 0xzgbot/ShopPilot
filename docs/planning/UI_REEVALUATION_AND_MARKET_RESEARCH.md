# ShopPilot UI Reevaluation + Market Research — "Open the doors" pass

**Date:** 2026-08-12
**Author:** Hermes agent (research: web sources below; reevaluation: full read of
`Sources/ShopPilot` shell code)
**User complaint addressed:** *"The UI still has a closed off ultra pro elitist look and
feel to it. New users of a CNC app will not want this."*
**Context:** Phase L (SPK-1201…1210) and the visual wave fixed the *"AI-built / bare-bones"*
problem by benchmarking against **Vectric Aspire 12.5** and polishing the chrome. That
benchmark is exactly the problem: Aspire is a $2,000 pro CAM suite, and ShopPilot now reads
like a *small Aspire* — dense, uppercase, panel-heavy, jargon-forward. This doc re-benchmarks
against the apps real first-time CNC **and** laser buyers actually open: LightBurn, xTool
Creative Space/Studio, Snapmaker Luban, Estlcam, Easel, Carbide Create.

**North-star for the next UI wave:** *"Creative first, powerful when you need it."* Keep every
pro capability; make the default view look and sound like a tool that wants to help a person
make their first thing this afternoon.

---

## 1. Executive summary

1. **The "elitist" read is real and it comes from the Aspire benchmark.** Three-pane pro shell,
   UPPERCASE section labels, 8 stacked Setup panels, "Stock, origin and machine" intents,
   dry legal-tone first run. Everything is *correct*, nothing is *inviting*.
2. **The top combined laser+CNC apps split into two UX camps**: LightBurn / Estlcam /
   LaserGRBL (power-first, utilitarian, hobby-pro) vs xTool Creative Space / Snapmaker Luban /
   Easel / Carbide Create (beginner-first, minimal chrome, presets + templates + guided
   next-step). The apps beginners *love* are all in the second camp — and none of them
   sacrifice power by doing it; they hide it.
3. **ShopPilot already owns the biggest beginner asset and it is unwired**: `SampleProjectsStore`
   (4 ready-made projects: sign, box, keychain, plaque) exists in Core, passes its verify CLT,
   and is referenced by **nothing in the app UI**. Snapmaker ships 1,000+ templates and that
   library is the #1 reason its software is called "intuitive." Wiring the store into the
   Welcome sheet is the single highest-ROI UI change available.
4. **Recommended direction (P0 this week):**
   - Welcome sheet → "Start making" with a **sample gallery** (4 cards, one click, lands in Design).
   - **Density pass**: collapse the 8 Setup panels to "Stock & Material" + an *Advanced* disclosure;
     make the Design stage's primary CTA a big "Make it →" advance button.
   - **Copy pass**: stage intents, empty states, status bar in plain warm English; kill uppercase
     micro-labels in the user-facing shell.
   - **Coach strip → tip card** with an action button ("Next: add your first shape").
5. **Laser story is the same table**: the Cut-Layers table (SPK-1201) is already the LightBurn
   pattern — when laser strategies land (Track 5 / SPK-0623) the combined-app positioning is
   already visible. The friendliness pass is what makes that positioning *feel* real.

---

## 2. Market research — apps that control laser cutters and CNC machines

### 2.1 The landscape (researched 2026-08-12)

| App | Platform | Price | Machines | UI character | Beginner read | Lesson for ShopPilot |
|---|---|---|---|---|---|---|
| **LightBurn** | Win / macOS (Linux frozen) | $99 Core / $199 Pro + ~$40/yr updates | Diode, CO2, fiber/galvo — near-universal laser; G-code | All-in-one design+control; powerful, dense, **utilitarian** | "Steeper learning curve… features initially overwhelming"; users call the UI clumsy, but tolerate it for capability | Power wins loyalty, not looks. Its **cut-layers table** is the pattern we already adopted (SPK-1201) |
| **xTool Creative Space / Studio** | Win, Mac, iPad, Android | Free (xTool only) | xTool lasers (+ newer CNCs in ecosystem) | **Minimalist, simple, friendly**; material library with auto settings; built-in AI (cutout/image); project library | The canonical "just make it" app; beginners start engraving with minimal setup | Minimal chrome + **presets over parameters** + **project gallery** = beginner confidence |
| **Snapmaker Luban** | Win / macOS | Free (Snapmaker) | 3D print + **laser + CNC** in one app | Intuitive, clearly separated sections, built-in tutorials/prompts | Reviewers: "intuitive and easy to use… ideal for users wanting to break into laser and CNC"; ships **1,000+ vector templates** | The exact **one-app-for-laser-and-CNC** model: friendly default, pro depth behind it |
| **Estlcam** | Windows | ~$60 | CNC routers + **laser** (same app) | Very user-friendly graphical UI, pop-up help everywhere | "Create your first cutting routes within minutes… definitely aimed at hobby use" | Cheap, hobby-first, one-app CNC+laser; help is inline, not a manual |
| **LaserGRBL** | Windows | Free (open source) | GRBL diode lasers + CNC | Lightweight controller: image→G-code, jog, frame | Simple but bare — a controller, not a companion | Baseline for "not scary" but lacks guidance; don't copy the bareness |
| **GRBL-Plotter / OpenBuilds / UGS** | Win / macOS / Linux | Free | Pen plotter + laser + CNC via GRBL | Utilitarian control panels | Hobbyist/tinkerer audience; no onboarding | Confirms control UIs can be friendly and still powerful |
| **Easel (Inventables)** | Web | Freemium | CNC (Shapeoko/X-Carve) | Guided, single big **"Carve"** CTA, one obvious path | Users: "Easel is definitely beginner-centric" | The **single primary CTA per screen** pattern |
| **Carbide Create + Motion** | Win / macOS | Free | CNC (Shapeoko/Nomad) | Friendly pastel UI, guided workflow | Beginner-friendly 2.5D CAM | Warm visual language without losing pro features |
| **Fusion 360** | Win / macOS | Free personal / paid | CNC + laser (post-processors) | Pro ribbon, enormous surface | Powerful, intimidating; not the friendliness benchmark | Do **not** copy the ribbon; progressive disclosure already chosen |

### 2.2 What the beginner-first apps share (the transferable patterns)

1. **Minimal chrome, lots of air.** XCS, Luban, Easel all keep the default screen sparse.
   Density reads as "this is for experts." ShopPilot's current default shows *both sidebars,
   the rail, a coach strip, and a status bar* at once.
2. **Presets over parameters.** XCS's material library auto-sets power/speed; Luban's machine
   presets; LightBurn's device library. New users pick *"walnut 3 mm"*, not *feed rate 1200*.
   ShopPilot already has the engines: `MaterialSurfacePalette.presets` (material swatches),
   `ManufacturerToolCatalog`, `ToolpathTemplateLibrary`, 4 sample projects. **Wire them in.**
3. **A gallery of ready-made projects on first run.** Snapmaker ships 1,000+ templates;
   XCS has a project library; LightBurn ships sample files. First cut within minutes.
   ShopPilot's store exists — unwired.
4. **One obvious next action per screen.** Easel's "Carve", XCS's big "Start", Luban's
   step prompts. ShopPilot's stages each have a *toolbar* but no single forward CTA.
5. **Plain language.** "Make", "cut", "create" — not "toolpath strategy", "stock", "origin".
6. **Help is inline and contextual** (Estlcam pop-ups, Luban built-in tutorials), not a
   documentation site. ShopPilot's coach strip is the seed — make it a real tip card.
7. **The safety conversation is still there — but warm.** Every vendor still teaches
   "frame before you fire"; none lead with it as the first screen's centerpiece.

### 2.3 Sources

- LightBurn vs XCS (creatorally.com, 2024; xTool support comparison; atomm.com 2026 roundup —
  LightBurn $99/$199, XCS/Studio free, LaserGRBL Windows-only)
- Snapmaker Luban (snapmaker.com; 3dprintingindustry.com Artisan review: "intuitive and easy to
  use… built-in tutorials and prompts… 1000+ laser vector templates")
- Estlcam (onefinity forum, v1e.com docs, sienci forum: "aimed at hobby use… first cutting
  routes within minutes")
- Easel ("beginner-centric" — Sienci Labs 2026 CNC software review comments)
- Makera beginner guide 2026 (beginner traits: simple interface, built-in tutorials, community)
- grouchyfarmer + forum sentiment on LightBurn's UI ("clumsy", worth it for capability)

---

## 3. Current UI reevaluation (grounded in the code)

### 3.1 What the shell actually is today

`ContentView.swift` = 46pt top chrome (document identity | 6-stage rail | machine pill +
safety controls) → alarm banner → **HSplitView** (Left panel 180–280pt | stage body |
Inspector 220–320pt) → 24pt status bar. Plus coach strip, ⌘K command palette, welcome sheet,
safety disclaimer sheet.

Design vocabulary (`DesignSystem.swift`): amber brand tint (0.93, 0.60, 0.18), `SectionLabel`
= **UPPERCASE + tracking** (Aspire/Xcode pattern), `.thinMaterial` sidebars with hairline
dividers, rounded-monospaced DRO numerals, spring animations. All tasteful, all *professional*,
none of it *welcoming*.

### 3.2 Why it reads "closed off, ultra pro, elitist" — itemized

| # | Symptom (code location) | Why it alienates a new user | Fix |
|---|---|---|---|
| 1 | **Welcome sheet is a routing dialog** — shipping box icon, three text buttons, legal-ish safety line (`WelcomeSheetView.swift`) | First impression is "pick a workflow," not "let's make something" | Reframe as a **Start Making** sheet: sample gallery first, "new job" second, files third |
| 2 | **Sample projects exist but are invisible** (`SampleProjectsStore` — referenced only by `ShopPilotVerify1313`) | The single strongest beginner asset in the codebase does nothing | Wire into Welcome + a "Samples" button on the Design empty state |
| 3 | **Uppercase micro-labels everywhere** (`SectionLabel`: `text.uppercased()` + tracking 0.6) | CAD-cockpit typography; says "pro tool, know the terms" | Keep for inspector column headers only; use sentence case in user-facing chrome |
| 4 | **Setup stage = wall of 8 pro panels** (`SetupStageView`: NewJob, Sheets, Double-Sided, Rotary, Material, Document Variables, Driven Dimensions, Golden Jobs) | A first-timer sees 8 panels; 5 are advanced | Collapse to **Stock & Material** first, everything else under an **Advanced** disclosure |
| 5 | **Stage intents are jargon** (`StageEnum.intent`: "Stock, origin and machine", "Toolpath strategies") | "Stock", "origin", "strategies" are not first-run vocabulary | "Set up your board", "Draw it or bring in a file", "Plan the cuts", "See it cut", "Connect your machine" |
| 6 | **No single forward CTA per stage** (Design opsBar is a tool row; Cut tree + toolbar) | Beginner doesn't know what "done" looks like | Big primary action per stage: "Add shapes →", "Plan cuts →", "Preview →", "Connect & run" |
| 7 | **Coach strip is a thin caption** (`CoachPanelView` under the rail) | Easy to miss; reads as decoration | Upgrade to a **tip card** (icon + sentence + action button), same `CoachRuleEngine` rules |
| 8 | **Status bar + "Edited" dot + toolpath summary** (`ContentView.statusBar`) | Engineering telemetry, not encouragement | Keep, but phrase in plain language; drop it entirely on first-run |
| 9 | **Empty states are correct but cold** ("Nothing drawn yet… Pick a tool above and draw straight onto the sheet") | Fine copy, tiny type, tertiary icon | One warm sentence + sample-gallery CTA + big "Import artwork" |
| 10 | **"Untitled Job" + `shop_pilot_pro_skip` flag in code** | "Job" is CAD-speak; "pro" naming leaks into the product | "Untitled Project"; rename the pref when convenient |

### 3.3 What is already right — do NOT regress

- **Six-stage rail** (Setup→Design→Model→Cut→Preview→Machine) is the right skeleton and
  already *is* progressive disclosure — label it so beginners can see the path.
- **Preview / material-surface sim** (SPK-1202, 1210) is the trust feature competitors envy.
- **Cut-Layers table** (SPK-1201) is the LightBurn pattern — laser+CNC ready.
- **Safety chrome** (E-stop, Hold/Reset always visible, alarm banner) is non-negotiable and
  stays exactly where it is.
- **Amber brand + router-bit icon + material swatch chips** — keep; they're warm already.
- **⌘K command palette, context menus, status chips** — pro depth kept, just de-emphasized.

### 3.4 Target feel (one paragraph)

Default window: rail up top, one sidebar (browser), big canvas, friendly stage headline that
answers "what do I do here?", one obvious forward button, and a tip card. Advanced panels
exist one click away under *Advanced / More*. Copy reads like a shop teacher, not a manual:
"Set up your board", "Draw it, or bring in an SVG/DXF", "See exactly what the bit will do".
First run: pick a sample → it opens on the Design stage → the coach card says "Next: plan the
cuts". Machine stage keeps the full safety discipline unchanged.

---

## 4. Ranked implementation menu (P0 → P2)

### P0 — Friendliness wave (highest ROI, all small, mostly wiring + copy)
1. **Wire `SampleProjectsStore` into the Welcome sheet** — "Start with a sample" grid (4 cards:
   name, tagline, category icon; click → `session.loadPackage(payload)` → Design stage).
   Engine + verify exist; needs a session load method (likely `replaceJob`-adjacent — grep
   `ShopPilotPackagePayload` handling before writing).
2. **Reframe Welcome copy** — headline + one sentence, sample grid, then New Job / Open /
   Import as secondary rows. Keep the safety line (friendlier wording).
3. **Setup stage reflow** — "Stock & Material" section first (NewJob + Material), the other
   six panels under a single **Advanced** `DisclosureGroup`.
4. **Copy pass** — `StageEnum.intent`, Design empty state, status bar, "Untitled Project".
   Sentence case for user-facing labels (leave inspector column headers uppercase).

### P1 — Momentum wave
5. **Primary forward CTA per stage** — prominent brand button at the end of each stage's
   toolbar: Design "Add shapes", Cut "Plan cuts", Preview "See the cut", Machine "Connect".
   First stage advance = 1 click from Welcome sample.
6. **Coach strip → tip card** — same `CoachRuleEngine`, card chrome (icon, sentence, action
   button when a rule has one), positioned above the status bar.
7. **Design empty state upgrade** — bigger type, sample CTA alongside Import.

### P2 — Polish wave
8. **First-run "how it works" overlay** — 15-second stage-rail walkthrough on the
   FirstRunGate (already exists) before the Welcome sheet.
9. **Sample gallery in Design stage too** ("Try a sample" in the empty state).
10. **Laser-ready framing** — when laser strategies land (Track 5), Cut-Layers table covers
    them; verify the table's tool column and status chips accept laser ops without new UI.

### Verification (repo convention)
- `swift test` full package + sweep must stay 0 FAIL (samples store already has
  `ShopPilotVerify1313` — a Welcome-sheet wiring test extends it or adds 1313b).
- New UI only touches `Sources/ShopPilot/*` — no Core churn except a session load-sample
  method (one line) if `replaceJob` isn't directly reusable.
- Visual check: launch app, first-run state, click every P0 path.

---

## 5. What we deliberately do NOT do

- No easy/expert product split (already decided; progressive disclosure chosen).
- No lightening of machine-stage safety chrome — E-stop/Hold/Reset stay fixed.
- No copy of Fusion's ribbon or Vectric's form-per-strategy spawning (Aspire benchmark doc §5).
- No removal of pro features to look friendly — hide, don't amputate.

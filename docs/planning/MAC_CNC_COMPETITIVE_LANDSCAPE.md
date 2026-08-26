# Mac CNC Software — Competitive Landscape Analysis

**Date:** 2026-08-09  
**Scope:** All major CNC software competitors, UI analysis, easy/expert mode survey, ShopPilot comparison

---

## 1. Competitor Breakdown

### 1.1 the incumbent vendor (V-carve / full 3D suite / entry 2D tier)

| Field | Value |
| --- | --- |
| **Platform** | Windows only (Mac users need Parallels) |
| **Products** | the entry 2D tier ($199), the V-carve desktop tier ($349), the V-carve pro tier ($799), the incumbent suite ($1,995) |
| **UI Pattern** | Classic Windows MDI — left panel = project tree, center = 2D/3D canvas, right panel = toolpath parameters, bottom = status bar |
| **Easy/Expert Mode** | **No toggle.** Single interface. their announced Mac entry product is the "entry-level" product — essentially a separate "easy" app |
| **Key Strengths** | V-Carve is the gold standard; 2.5D decorative carving; 3D relief tools; 600+ pre-made relief models; extensive gadget ecosystem; 964+ post processors |
| **Key Weaknesses** | Windows-only; expensive ($349–$1,995); the V-carve pro tier is bloated for hobbyists; no native Mac support; cloud-dependent tutorials |

**UI Layout:** Left sidebar (project tree with vectors/toolpaths), center canvas (2D top-down + 3D view toggle), right panel (toolpath parameters with strategy-specific forms), bottom status bar. Dense, feature-packed interface.

---

### 1.2 Carveco (Maker / Maker Plus / Pro)

| Field | Value |
| --- | --- |
| **Platform** | Windows only (Mac users need Parallels) |
| **Products** | Maker ($40/mo or $900 perpetual), Maker Plus ($50/mo or $1,500 perpetual), Pro (premium) |
| **UI Pattern** | Palette-based — floating palettes for tools, toolpaths, materials that can be resized/moved. Central canvas. Right-side toolpath parameter panel |
| **Easy/Expert Mode** | **Yes — Maker vs Maker Plus vs Pro.** Three tiers with progressive feature gating. Maker is the "easy" tier (basic 2D + V-Carve), Maker Plus adds 3D + nesting + production tools, Pro is full power. Closest thing to "easy vs expert" in the market |
| **Key Strengths** | 3D sculpting tools (Smooth/Erase); Shape Editor; AI tools (Prompt to Relief, Image to Relief); nesting; 600+ relief models; 3D PDF export; material simulation; 300+ post processors |
| **Key Weaknesses** | Windows-only; subscription model ($50/mo); expensive; AI tools require subscription; no native Mac |

**UI Layout:** Palette-based floating panels (can be docked or floating). Central canvas. Toolpath parameters on right. More modern/clean than the incumbent but still Windows-style.

---

### 1.3 MillMage (Core / Pro)

| Field | Value |
| --- | --- |
| **Platform** | **Windows AND macOS** (native on both) |
| **Products** | Core ($99), Pro ($199), $50/year for updates |
| **UI Pattern** | Single-window layout — left panel = project tree, center = canvas, right panel = toolpath parameters. Modern, clean UI. Similar to the incumbent but more streamlined |
| **Easy/Expert Mode** | **Yes — Core vs Pro.** Core is the "easy" tier (basic 2D CAM), Pro adds V-Carving, Relief, nesting, and advanced features. Most direct parallel to ShopPilot's planned $99/$199 pricing |
| **Key Strengths** | One of the few Mac-native CNC apps; affordable ($99/$199); single-window design; combines design/CAM/control in one; from LightBurn team (proven track record); perpetual licensing |
| **Key Weaknesses** | New product (launched Feb 2026); limited feature set in Core; V-Carving only in Pro; smaller ecosystem; fewer posts; less mature |

**UI Layout:** Clean single-window. Left panel = tree (vectors + toolpaths), center = canvas, right = parameters. Modern, minimal chrome. More streamlined than the incumbent.

---

### 1.4 Carbide Create (Core / Pro)

| Field | Value |
| --- | --- |
| **Platform** | Windows and macOS |
| **Products** | Core (free), Pro ($120/yr or $360 perpetual) |
| **UI Pattern** | Simple, single-panel — left sidebar (vectors + toolpaths), center canvas, right panel (toolpath settings). Very beginner-friendly. Minimal chrome |
| **Easy/Expert Mode** | **Yes — Core (free) vs Pro (paid).** Core handles 2D + basic 2.5D. Pro adds 3D modeling, rest machining, STL import, tiling, standard G-code export. The free Core is genuinely "easy mode" |
| **Key Strengths** | Free tier; very beginner-friendly; works with any CNC (not just Shapeoko); saves standard G-code; Mac support |
| **Key Weaknesses** | Limited to 2D/basic 2.5D in free version; no V-Carve; no nesting; limited toolpaths; no machine control (separate app: Carbide Motion); no 3D in Core |

**UI Layout:** Extremely clean. Left sidebar (project tree), center canvas, right panel (toolpath settings). Very approachable for beginners. Minimal learning curve.

---

### 1.5 Easel (Web-based)

| Field | Value |
| --- | --- |
| **Platform** | **Web browser** (Chrome, works on Mac) |
| **Products** | Free (limited), Pro subscription |
| **UI Pattern** | Web app — left panel = tools + vectors, center = canvas with 3D preview, right panel = toolpath settings. Very simplified |
| **Easy/Expert Mode** | **Yes — Free vs Pro.** Free is basic 2D + 3D carving. Pro adds advanced features. The web interface is inherently "easy mode" — no installation, no complexity |
| **Key Strengths** | No installation; works on any device with browser; very beginner-friendly; 3D carving built-in; project gallery for inspiration |
| **Key Weaknesses** | Web-only (requires internet); no offline capability; limited features; no machine control; no V-Carve; no nesting; no advanced toolpaths |

**UI Layout:** Web-based, simplified. Left panel = tools, center = canvas, right = settings. Very stripped down.

---

### 1.6 MeshCAM (Windows only)

| Field | Value |
| --- | --- |
| **Platform** | Windows only |
| **Products** | Various tiers (check website) |
| **UI Pattern** | Wizard-driven — step-by-step toolpath creation. Simple, linear workflow. Left panel = operations tree, center = preview, right = parameters |
| **Easy/Expert Mode** | **Yes — Wizard mode vs manual mode.** The wizard guides beginners through toolpath creation step-by-step. Advanced users can access manual parameter editing |
| **Key Strengths** | Very easy to learn; wizard-driven workflow; 3D CAM focused; good for non-machinists |
| **Key Weaknesses** | Windows-only; limited 2D capabilities; no machine control; no V-Carve; smaller ecosystem |

---

### 1.7 gSender (Control-Only)

| Field | Value |
| --- | --- |
| **Platform** | Windows, macOS, Linux, Raspberry Pi |
| **Products** | Free (with paid Pro features) |
| **UI Pattern** | Control-focused — no design/CAM, just machine control. Left panel = controls, center = console, right = settings. Modern UI |
| **Easy/Expert Mode** | **No toggle, but inherently simple.** It's a control-only app, so the interface is naturally streamlined |
| **Key Strengths** | Cross-platform; free; real-time toolpath visualization; macros; work coordinate systems; probing; works with any GRBL controller |
| **Key Weaknesses** | No design or CAM — just machine control; no toolpath generation; no 3D; no V-Carve |

---

### 1.8 Autodesk Fusion (formerly Fusion 360)

| Field | Value |
| --- | --- |
| **Platform** | Windows and macOS (native) |
| **Products** | Subscription ($635/yr), free personal license (limited) |
| **UI Pattern** | Modern ribbon UI — top ribbon = commands, left panel = browser tree, center = 3D viewport, right panel = parameters. Professional CAD/CAM interface |
| **Easy/Expert Mode** | **No toggle, but "T-Splines" mode is simplified.** The interface is inherently complex (professional CAD/CAM/CAE all-in-one) |
| **Key Strengths** | Full CAD + CAM + CAE in one; 2D/3D/4D/5-axis machining; cloud collaboration; professional-grade; Mac native; extensive post processor library |
| **Key Weaknesses** | Expensive ($635/yr); cloud-dependent (subscription); complex interface (steep learning curve); no dedicated CNC machine control; overkill for hobbyists |

---

### 1.9 PlanetCNC TNG (Control-Only)

| Field | Value |
| --- | --- |
| **Platform** | Windows only |
| **Products** | Free controller + software |
| **UI Pattern** | Control-focused — machine control interface with status display, jog controls, console. No design/CAM |
| **Easy/Expert Mode** | **No toggle.** Single control interface |
| **Key Strengths** | Free; works with PlanetCNC controllers; real-time control; G-code export |
| **Key Weaknesses** | Control-only (no design/CAM); Windows-only; limited to PlanetCNC ecosystem |

---

## 2. "Easy Mode vs Expert Mode" — Market Survey

**Yes, several competitors offer this pattern:**

| App | Easy Mode | Expert Mode | How |
| --- | --- | --- | --- |
| **Carveco** | Maker (basic 2D + V-Carve) | Maker Plus / Pro (3D, nesting, production) | Separate products, not a toggle |
| **MillMage** | Core ($99) | Pro ($199) | Separate products, not a toggle |
| **Carbide Create** | Core (free, 2D/2.5D) | Pro ($120/yr, adds 3D) | Separate products, not a toggle |
| **Easel** | Free (basic) | Pro (advanced) | Subscription tiers |
| **MeshCAM** | Wizard mode | Manual mode | **Toggle within the same app** |
| **Incumbent** | Spark (Mac entry-level) | V-carve pro tier / full 3D suite | Separate products |
| **ShopPilot** | Recipe-driven onboarding + progressive chrome | Full stage-rail UI | **Progressive disclosure** (not separate modes) |

**Key insight:** Most competitors use **separate products** (Maker vs Maker Plus, Core vs Pro) rather than a toggle within a single app. MeshCAM is the notable exception with an in-app wizard/manual toggle. ShopPilot's approach of **progressive disclosure** (recipe-driven onboarding for beginners, full stage-rail for experts) is actually more elegant — one app, no confusion about which version you have.

---

## 3. ShopPilot vs Competitors — Feature Parity

### 3.1 Where ShopPilot is ahead

| Area | ShopPilot | Competitors |
| --- | --- | --- |
| **Native Mac** | ✅ SwiftUI, Apple Silicon native | ❌ Most are Windows-only; Fusion is the only other Mac-native option |
| **All-in-one** | ✅ Design + CAM + Control in one app | ❌ Most are split (CAM app + separate control app like gSender) |
| **Offline-first** | ✅ No cloud dependency | ❌ Fusion requires subscription/cloud; Easel is web-only |
| **Pricing** | ✅ $99/$199 perpetual | ❌ the incumbent $349–$1,995; Carveco $900–$1,500; Fusion $635/yr |
| **Recipe-driven onboarding** | ✅ Sign/Cabinet/Relief/Inlay recipes | ❌ None offer this approach |
| **Stage-rail UI** | ✅ Progressive chrome, no clutter | ❌ Most have dense, feature-heavy interfaces |
| **Machine control built-in** | ✅ Sim + serial, Hold/Reset always visible | ❌ Most CAM apps only export G-code |

### 3.2 Where ShopPilot is catching up

| Area | ShopPilot Status | Competitor Baseline |
| --- | --- | --- |
| **2D design** | ✅ Profile/Pocket/Drill/V-Carve + boolean ops + layers | ✅ Carveco have mature 2D editors |
| **V-Carve** | ✅ Clearance tool + V-bit (lean implementation) | ✅ the incumbent is the gold standard |
| **3D carving** | ✅ STL→heightfield→rough/finish G-code (in progress) | ✅ Carveco have mature 3D |
| **Preview** | ✅ Wireframe + draft sim (in progress) | ✅ Carveco have material simulation |
| **Posts** | ✅ GRBL-class (in progress) | ✅ 964+ posts (the incumbent), 300+ (Carveco) |
| **Nesting** | ❌ Not yet | ✅ Carveco Pro |
| **Rotary/4-axis** | ❌ Not yet | ✅ Carveco |
| **Laser** | ❌ Not yet | ✅ the incumbent laser module |
| **Toolpath templates** | ❌ Not yet | ✅ Carveco |
| **Double-sided** | ❌ Not yet | ✅ Carveco |

---

## 4. UI Layout Comparison

| App | Layout Style | Panels | Canvas | Learning Curve |
| --- | --- | --- | --- | --- |
| **ShopPilot** | Stage-rail (Design→Cut→Preview→Machine) | Left browser, right inspector | Full canvas per stage | Moderate (progressive) |
| **Incumbent** | Classic MDI | Left tree, right params | Center canvas (2D/3D toggle) | Steep |
| **Carveco** | Palette-based | Floating palettes, right params | Center canvas | Moderate |
| **MillMage** | Single-window | Left tree, right params | Center canvas | Gentle |
| **Carbide Create** | Simplified | Left sidebar, right params | Center canvas | Very gentle |
| **Easel** | Web app | Left tools, right params | Center canvas | Very gentle |
| **Fusion** | Ribbon UI | Left browser, right params | 3D viewport | Steep |
| **gSender** | Control-focused | Left controls, right settings | Console view | Gentle |

---

## 5. Recommendations for ShopPilot

### 5.1 "Easy Mode" — Don't build it as a toggle

The market data shows that **separate products** (Maker vs Maker Plus) is the dominant pattern, but ShopPilot's **progressive disclosure** approach is actually superior:

- **Recipe-driven onboarding** (Sign/Cabinet/Relief/Inlay) = "easy mode" for beginners
- **Stage-rail UI** = experts can access full power without clutter
- **⌘K command palette** = power users can skip UI entirely

This is better than a toggle because:
1. No confusion about which version you have
2. No feature gating within the same app
3. One codebase, one UI

### 5.2 Key differentiators to emphasize

1. **Native Mac** — This is the #1 selling point. Most competitors force Mac users into Parallels.
2. **All-in-one** — Design + CAM + Control in one app (competitors split these)
3. **Offline-first**
4. **Pricing** — $99/$199 perpetual vs $349–$1,995 perpetual or $635/yr subscription
5. **Recipe-driven onboarding** — No other CNC app does this

### 5.3 Priority features to close gaps

1. **V-Carve quality** — Match the incumbent's clearance tool chain (lean implementation)
2. **3D relief pipeline** — STL→heightfield→rough/finish G-code (in progress)
3. **Material simulation** — Sheet-aware preview (in progress)
4. **Toolpath templates** — Carveco have this
5. **Nesting** — Production feature, post-v1

---

## 6. Pricing Comparison

| App | Entry Price | Full Price | Model |
| --- | --- | --- | --- |
| **Carbide Create** | Free | $120/yr or $360 perpetual | Freemium |
| **MillMage** | $99 (Core) | $199 (Pro) | Perpetual |
| **ShopPilot (planned)** | $99 (Core) | $199 (Pro) | Perpetual |
| **Incumbent — entry 2D tier** | $199 | $199 | Perpetual |
| **Incumbent — V-carve desktop tier** | $349 | $349 | Perpetual |
| **Incumbent — V-carve pro tier** | — | $799 | Perpetual |
| **Incumbent — full 3D suite** | — | $1,995 | Perpetual |
| **Carveco Maker** | $40/mo | $900 perpetual | Sub or perpetual |
| **Carveco Maker Plus** | $50/mo | $1,500 perpetual | Sub or perpetual |
| **Autodesk Fusion** | Free (limited) | $635/yr | Subscription only |
| **Easel** | Free | Pro subscription | Web subscription |
| **gSender** | Free | Pro features | Freemium |

**ShopPilot's pricing ($99/$199 perpetual) undercuts everyone except the free tiers.** It's positioned between MillMage and Carbide Create Pro — affordable but not "cheap."

---

*Analysis compiled 2026-08-09 from competitor websites, documentation, and community forums.*

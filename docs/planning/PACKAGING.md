# ShopPilot Packaging & Distribution Strategy

**Version:** 0.1.0  
**Last Updated:** 2026-07-31

---

## Product Tiers

### Tier 1 — ShopPilot Core (Free / Base)

| Feature | Status | Notes |
|---------|--------|-------|
| Native Apple Silicon app | ✅ | SwiftUI, macOS 14+ |
| Single-sided stock, layers, undo, save/open `.shoppilot` | ✅ | Core document model |
| Draw/edit vectors: line, arc, circle, rectangle | ✅ | Kernel.swift |
| Node editing, transform (move/rotate/scale), group | ✅ | NodeEditor.swift, Transform.swift |
| Offset vectors, boolean weld/subtract/intersection | ✅ | VectorOffset.swift, BooleanOperations.swift |
| Join/close/trim, measure tool | ✅ | JoinCloseTrim.swift, MeasurementTool.swift |
| SVG import | ✅ | SVGImporter.swift |
| DXF import | ⏳ Drafted | Not yet passing build; removed from shipping target |
| Tool database v0 (endmill, V-bit) | ✅ | ToolDatabase.swift |
| Material setup | ⏳ Planned | SPK-0300 |
| Profile / Pocket / Drill toolpaths | ❌ Not started | SPK-0302–0304 |
| Draft/Final preview (heightfield) | ❌ Not started | SPK-0309–0310 |
| GRBL post export (.nc) | ❌ Not started | SPK-0313 |
| Simulator connection + jog + stream | ⏳ Scaffolded | Transport + StatusParser + GCodeStreamer present; jog/stream UI not done |
| Pre-flight checklist | ❌ Not started | SPK-0412 |
| ⌘K command palette, stage rail ≤12 icons | ✅ | Commands.swift, StageRailView.swift, IconEnforcement.swift |

**No 3D. No V-Carve. No text-to-curves. No laser for v1.0.**

### Tier 2 — ShopPilot Studio (Paid Unlock)

Adds to Core:
- **Import:** SVG done; DXF in progress
- **Text:** System fonts, text-to-curves, text-on-curve
- **V-Carve strategy** (field map from DOC calibration pack)
- **Quick engrave** strategy
- **Keep-out zones v0**
- **Toolpath templates** save/load
- **Job sheet PDF** export

### Tier 3 — ShopPilot Studio 3D (Paid Unlock)

Adds to Studio:
- **Component + Level model** with browser
- **Combine modes:** Add / Subtract / Merge / Low
- **Dynamic height/tilt/fade, shape tools** (angled, round, smooth, flat)
- **Bitmap → component**, import STL
- **3D rough + finish toolpaths**
- **Sculpt mode v1**

---

## Feature Flag Architecture

The three-tier model is enforced at runtime via `FeatureFlag` and `ProductTier` in `ShopPilotCore/FeatureFlag.swift`.  
`StageGate` in `ShopPilotCore/StageGate.swift` gates stage-level UI access.  
`Stage.isAvailable(tier:)` in `StageEnum.swift` gates individual stage rail buttons.

### Tier feature matrix

Feature | Core | Studio | Studio3D
---------|------|--------|----------
2D vector design | ✅ | ✅ | ✅
Profile/Pocket/Drill toolpaths | ✅ | ✅ | ✅
Preview simulation | ✅ | ✅ | ✅
GRBL machine control | ✅ | ✅ | ✅
Text (system fonts, text-to-curves) | ❌ | ✅ | ✅
V-Carve strategy | ❌ | ✅ | ✅
Quick engrave | ❌ | ✅ | ✅
Keep-out zones | ❌ | ✅ | ✅
Toolpath templates | ❌ | ✅ | ✅
Job sheet PDF | ❌ | ✅ | ✅
Component browser / combine modes | ❌ | ❌ | ✅
3D rough/finish toolpaths | ❌ | ❌ | ✅
Sculpt mode | ❌ | ❌ | ✅
STL/OBJ import | ❌ | ❌ | ✅

### Enforcement points

1. **FeatureFlag.isAvailable(feature, tier)** — All UI code calls this before showing a feature. Core features (`.vectorDesign2D`, `.coreToolpaths`, `.previewSimulation`, `.machineControl`) always return `true`. Studio features require `.hasStudio`. 3D features require `.has3D`.
2. **StageGate.canUseModelStage(tier)** — Returns `tier.has3D`. Core/Studio see the Model stage with an upgrade prompt.
3. **Stage.isAvailable(tier)** — `Stage.model` returns `tier.has3D`. All other stages always available.
4. **StageGate.shouldHideModelStage(tier)** — Always returns `false`. The Model stage is never hidden from the rail; it shows an upgrade prompt for non-3D tiers.
5. **Commands.availableCommands(tier)** — Filters command palette entries by tier.

### Upgrade policy

- When a user upgrades from Core → Studio, Studio features appear as enabled options in the UI.
- When a user upgrades from Studio → Studio3D, the Model stage becomes fully functional.
- All `.shoppilot` files remain fully compatible across tiers — no data migration needed.

---

## Laser Policy

Laser cutting is **NOT included in any tier for v1.0**.

Rationale:
- Laser requires different hardware (different controller, not GRBL-compatible)
- Safety considerations differ significantly from rotary tools
- Can be added as a post-v1 feature with separate safety documentation

**Future:** SPK-0906 (Laser cut/fill/picture) is tracked on the kanban for v1.3+.

---

## Upgrade Policy

### From Core → Studio
- User purchases unlock key (future: in-app purchase or license file)
- All existing `.shoppilot` files remain fully compatible
- New features appear as enabled options in the UI
- No data migration required

### From Studio → Studio 3D
- Same model: unlock key enables additional stages and tools
- Component browser appears alongside Layer browser
- 3D toolpath strategies become available in Cut stage

### Downgrade / License Expiry
- If license expires, app reverts to Core tier features
- Existing files open normally but locked features are grayed out
- No data loss — all geometry and toolpaths preserved

---

## Distribution Channels

| Channel | v1.0 Status | Notes |
|---------|-------------|-------|
| Direct download (website) | ✅ Planned | DMG bundle, notarized |
| Mac App Store | ❌ Post-v1 | Requires Apple Developer account (SPK-0615) |
| GitHub Releases | ✅ Planned | Private repo now; public release artifact on v1.0 tag |

---

## Technical Packaging Notes

### Build Target
- **macOS 14.0+** minimum deployment target
- **Apple Silicon native** (arm64); Rosetta 2 fallback not required for v1.0
- **Xcode 15+** / Swift 5.9+ toolchain

### Bundle Structure
```
ShopPilot.app/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/ShopPilot          # Binary
│   ├── Resources/               # Assets, icons
│   └── Frameworks/              # Any bundled frameworks (none planned)
```

### Notarization (SPK-0621)
- Requires Apple Developer Program membership ($99/year)
- `codesign` + `xcrun notarytool submit` in CI pipeline
- Gatekeeper-staple step for offline verification

---

## Current phase status (2026-07-31)

| Phase | Status |
|-------|--------|
| Phase A — Packaging / platform bootstrap | ✅ Complete |
| Phase B — Mac-native shell | ✅ Complete |
| Phase C — Geometry core | ⏳ In progress (9/14 cards done) |
| Phase D — Toolpath core | ⏳ Scaffold only |
| Phase E — Machine control | ⏳ Core types done; UI/loop not done |
| Phase F — Sign shop | ❌ Not started |
| Phase G — v1.0 gate | ⏳ Docs done; QA/hardware flight pending |
| Phase H–K — 3D / production / rotary / v2.0 | ❌ Post-v1 |

---

## References

- **SPK-0005** (this document) — packaging truth before bulk code
- **SPK-0613** DISTRIBUTION.md — notarize steps, signing workflow
- **SPK-0621** Notarized build pipeline
- **SPK-0622** v1.0 tag + GitHub/release artifact
- **MASTER_KANBAN.md** — single source of truth for all SPK cards

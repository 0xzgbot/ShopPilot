# ShopPilot Packaging & Distribution Strategy

**Version:** 0.1.0  
**Last Updated:** 2026-07-29

---

## Product Tiers

### Tier 1 — ShopPilot Core (Free / Base)
| Feature | Included? |
|---------|-----------|
| Native Apple Silicon app | ✅ |
| Single-sided stock, layers, undo, save/open `.shoppilot` | ✅ |
| Draw/edit vectors: line, arc, circle, rectangle | ✅ |
| Node editing, transform (move/rotate/scale), group | ✅ |
| Offset vectors, boolean weld/subtract/intersect | ✅ |
| Join/close/trim, measure tool | ✅ |
| Profile, Pocket, Drill toolpaths | ✅ |
| Material setup + tool database v0 | ✅ |
| Draft/Final preview (heightfield) | ✅ |
| GRBL post export (.nc files) | ✅ |
| Simulator connection + jog + stream | ✅ |
| Pre-flight checklist | ✅ |
| ⌘K command palette, stage rail ≤12 icons | ✅ |

**No 3D. No V-Carve. No text-to-curves. No DXF import.**

### Tier 2 — ShopPilot Studio (Paid Unlock)
Adds to Core:
- **Import:** SVG + DXF
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
| GitHub Releases | ✅ Planned | Free tier only; Studio features require license key |

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

## References

- **SPK-0005** (this document) — packaging truth before bulk code
- **SPK-0613** DISTRIBUTION.md — notarize steps, signing workflow
- **SPK-0621** Notarized build pipeline
- **SPK-0622** v1.0 tag + GitHub/release artifact

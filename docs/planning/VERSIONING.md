# ShopPilot — Versioning & Release Scheme

**Date:** 2026-07-28  
**Standard:** Semantic Versioning (SemVer) 2.0.0

---

## Format

```
MAJOR.MINOR.PATCH
```

### MAJOR version (X.y.z)
Incremented for incompatible API or architecture changes:
- New product tier structure that breaks backward compatibility
- Major UI/UX overhaul requiring users to relearn workflows
- Changes to the `.shoppilot` file format that prevent opening older files
- Removal of features present in the previous major version

### MINOR version (x.Y.z)
Incremented for backwards-compatible feature additions:
- New toolpath strategies (e.g., adding Thread Milling, Fluting)
- New design tools (e.g., Text on Curve, Trace Bitmap)
- New stages or features within existing stages
- Support for new file formats (new import/export options)
- Significant UX improvements that don't break workflows

### PATCH version (x.y.Z)
Incremented for backwards-compatible bug fixes:
- Toolpath calculation corrections
- Crash fixes
- G-code output formatting fixes
- UI polish and minor bug fixes
- Performance optimizations

---

## Version Numbering Plan

| Version | Scope | Description |
|---------|-------|-------------|
| **0.1.x** | Pre-release | Early development, internal testing, no stability guarantees |
| **1.0.0** | v1.0 Ship | All Phase A–G cards complete. Core 2D CAM suite for Mac. |
| **1.1.x** | v1.1 Patch series | Bug fixes and minor improvements on the v1.0 foundation |
| **1.2.0** | v1.2 Release | Production features: multi-sheet, double-sided, inlays, nesting |
| **1.3.0** | v1.3 Release | Rotary, laser, specialty toolpaths (fluting, texture, prism) |
| **2.0.0** | v2.0 Release | Power user features: Post Studio, machine catalog online, plugin API |

---

## Changelog Format

Follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format:

```markdown
# Changelog

## [1.0.0] - 2026-XX-XX
### Added
- Native macOS app with SwiftUI
- Vector design tools (draw, edit, import SVG/DXF)
- Core toolpaths: Profile, Pocket, Drill, V-Carve
- Material simulation preview
- GRBL post-processor export
- Simulator transport for testing

### Fixed
- [Bug description]

### Changed
- [Change description]
```

---

## Tagging Convention

Git tags follow the version number exactly:
```bash
git tag -a v1.0.0 -m "ShopPilot 1.0.0 — First release"
git push origin v1.0.0
```

Pre-release tags use hyphen suffixes:
```bash
git tag -a v0.9.0-rc1 -m "Release candidate 1 for 0.9.0"
```

---

## Release Process

1. All Phase G exit criteria are `[x]` in MASTER_KANBAN.md
2. Run full test suite: `swift test` — all green
3. Build release artifact: `scripts/build.sh --release`
4. Sign and notarize the DMG (see DISTRIBUTION.md)
5. Create GitHub Release with changelog entries
6. Attach signed `.dmg` as release asset
7. Publish SHA-256 checksum alongside download

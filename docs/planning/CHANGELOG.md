# Changelog

All notable changes to ShopPilot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- Native macOS app shell with SwiftUI (Phase B)
- Stage rail UI: Setup | Design | Model | Cut | Preview | Machine
- Document model v0: Job, Sheet, Layer, undo, dirty doc
- Save/open `.shoppilot` package format with autosave and crash recovery
- Browser panels: Layers, Components, Toolpaths, Sheets
- Inspector shell with Essentials/Advanced disclosure groups
- ⌘K command palette framework with stub commands
- Preferences panel: units, theme, pro-skip checklist
- Job recipe picker (blank, calibration, sign)
- Vector kernel: polyline, arc, circle, rect (Phase C)
- Node editing, transform, align, group operations
- Offset vectors, boolean weld/subtract/intersection
- Join/close/trim vector operations
- SVG + DXF import support
- Layers CRUD with visibility controls
- Measure tool and calculation numeric fields
- Vector Preflight Doctor with plain-English fix actions (Phase C)
- Material setup for flat jobs (Phase D)
- Tool database v0: endmill, V-bit
- Profile toolpath with out/in/on cutting + tabs support
- Pocket toolpath strategy
- Drill toolpath strategy
- Toolpath tree with dirty badges (no silent auto-recalculation)
- Recalculate dirty/all toolpaths command
- Export block while dirty with expert override (Phase D)
- Keep-out zones v0
- Heightfield preview simulation + wireframe rendering
- Draft vs Final preview modes with progressive refinement
- Metal-backed preview path for stable viewport
- Rough time estimate calculation
- GRBL post-processor export with extension labeling
- Vector selector for toolpath strategies (Phase D)
- Serial configuration and machine profile models (Phase E)
- Machine transport protocol abstraction
- Simulator transport (fake GRBL) for testing without hardware
- Status parser with unit tests
- G-code streamer with ok-wait flow, hold/resume/reset controls
- Machine session facade with status polling (Phase E)
- Real serial enumerate + open/read/write on macOS
- Transport factory: simulator vs serial selection
- Machine UI: connect button, console output, status strip
- Safety chrome: always-on Hold and Reset buttons during machine operation
- Jog controls, soft home, work zero setup (Phase E)
- Stream job from file with progress indicator
- Pre-flight checklist before Run command
- One-click Run CTA when armed (Phase E)
- Cut stage to Machine stream handoff (STU integration)
- Post auto-select from machine profile (Phase E)
- Text tool and system font support (Phase F)
- Text to curves conversion
- V-Carve strategy with field map generation
- Quick engrave toolpath
- Trace bitmap functionality
- Text on curve (Phase F)
- Engraving font pack (Phase F)
- Nesting engine (shelf-packing + grid) (Phase F)
- Toolpath templates save/load
- Job sheet PDF export
- Document variables panel v0 (Phase F)
- Base tier path works without 3D unlock (FeatureFlag + StageGate) (Phase G)

### Fixed
- VectorOffset: full-circle input now samples full circumference (was 1-point path)
- ShapeJoinEngine: chain-join extends away from coincident point (was dropping segments)
- LayerManager: shape deletion uses value-based lookup (was broken Identifiable cast)
- PreflightReport: worstSeverity uses max (was using min — returned least severe)
- RealSerialTransport: open() uses forUpdatingAtPath (was forWritingAtPath — killed RX)
- Bug fixes will be added as they are discovered

---

## [1.0.0] — Planned Ship Version

### Added
- All Phase A–G features listed above
- README with Mac-native positioning and feature overview
- SAFETY.md with compliance guidelines and in-app disclaimer
- End-user first-cut tutorial (TUTORIAL_FIRST_CUT.md)
- Keyboard shortcut reference (KEYBOARD_SHORTCUTS.md)
- Distribution guide with notarization steps (DISTRIBUTION.md)
- Product tier strategy: Control / Studio2D / Studio3D (PACKAGING.md)
- Preflight rules document (PREFLIGHT_RULES.md)
- Versioning scheme and release process (VERSIONING.md)

### Quality Gates Met
- Calibration job E2E on simulator green
- All core unit tests passing in CI
- Dirty toolpath export blocked without override
- Preflight blocks V-Carve on open vectors with fix CTA
- Stage density audit: ≤12 icons per stage confirmed
- Hold/Reset visible whenever machine is connected
- Base tier path works without 3D unlock

---

## [0.9.x] — Pre-release Development

### Added
- Project scaffolding and architecture decision records
- Feature parity matrix against Aspire V12
- UX stage system design with anti-bloat rules
- Product boundaries document (relief CAM only, no solid CAD)
- Aspire form index crawl (218 URLs across all chapters)

# ShopPilot Phase L — UX Overhaul (v2.1)

**Date:** 2026-08-10
**Scope:** 10 UX/ease-of-use features closing the gap vs Vectric Aspire 12.5 +
forum pain points, plus pain-point alleviation baked into the same wave.
**DoD (repo convention):** Engine + UI + Persist + Verify CLT per card
(`ShopPilotVerify120x` PASS, whole-package build green, board `[x]` + worklog).

---

## 1. Pain points → alleviation map

| Pain point (source) | Alleviated by |
| --- | --- |
| Toolpath tree is opaque — can't see status/order/feeds at a glance (Aspire 12.5 "visual toolpath status" is the #1 tree complaint) | **SPK-1207** status chips + **SPK-1201** cut-layers table |
| "What you see isn't what you cut" — preview trust gap (forum theme #5, Aspire surface-color sim) | **SPK-1202** material-surface preview + **SPK-1210** toolpath-on-hover |
| Slow recalc on complex designs (forum theme #4) | **SPK-1207** Recalc-All + per-op status (see what's stale, fix only that) |
| Form-hopping: change a dim → find the form (Aspire 12.5 editable dimensions, smart part selection) | **SPK-1203** canvas dimension handles + smart part selection |
| Actions hidden in top bars (Aspire 12.5 sheet-transfer/bake/duplicate right-click pattern) | **SPK-1204** context menus everywhere |
| New users lost on first run (forum theme #8 docs/tutorials; Aspire 3D interactive help) | **SPK-1205** inline coach strip |
| 3D views feel flat/uncontrolled (Aspire V12 view control + orthographic) | **SPK-1206** nav gizmo + ortho toggle |
| Multi-sheet: copying a sheet/op is manual (Aspire 12.5 sheet duplication + toolpath transfer) | **SPK-1208** sheet duplication + toolpath sheet transfer |
| Import friction: formats + re-importing work (Aspire 12.5 WebP + unified import) | **SPK-1209** WebP import + recent-files rail |
| Peck drills invisible in sim; which op is that path? (Aspire 12.5 peck viz) | **SPK-1210** peck-drill viz + toolpath-on-hover |

## 2. Cards (SPK-1201 … SPK-1210)

### Wave 1 — foundation & quick wins (parallelizable)

#### SPK-1207 — Visual toolpath status + Recalc All
- **Engine:** `ToolpathStatusEngine` (Core): derives per-node status from dirty
  marks + toolpathResult presence — `.stale` (edited/dirty), `.current`
  (computed), `.error` (blocking issue). Plus `recalcAll(tree)` that
  regenerates every stale node in tree order (reuses existing per-op
  regenerators).
- **UI:** status dot in `ToolpathTreeView.swift` rows (gray/green/orange/red)
  + "Recalc All" button in the Cut toolbar.
- **Verify:** `ShopPilotVerify1207` — dirty-mark derivation, stale→current
  transition, recalc-all regenerates only stale nodes, siblings untouched.
- **Files:** `Sources/ShopPilotCore/ToolpathStatusEngine.swift` (new),
  `ToolpathTreeView.swift`, `ContentView.swift`, `Package.swift`.

#### SPK-1209 — WebP import + recent-files rail
- **Engine:** WebP decode (ImageIO `CGImageSourceCreateWithURL` — WebP is
  supported by ImageIO on macOS 11+) in the existing bitmap import path;
  `RecentFilesStore` (UserDefaults, capped 10) recording import URLs.
- **UI:** `ImportHubView.swift` gains a Recent rail (click to re-import);
  bitmap importer accepts `.webp`.
- **Verify:** `ShopPilotVerify1209` — WebP decodes to a raster (fixture in
  `fixtures/import/`), recent store cap + dedupe + persist.
- **Files:** `Sources/ShopPilotCore/RecentFilesStore.swift` (new),
  `ImportHubView.swift`, bitmap importer, `fixtures/import/` (1 webp),
  `Package.swift`.

#### SPK-1206 — View control gizmo + orthographic toggle
- **Engine:** `ViewOrientation` presets (front/top/right/isometric) + ortho
  flag on the preview/view state; gizmo hit-test math (cube face → preset).
- **UI:** nav cube overlay in `ToolpathPreviewView.swift` + `ModelStageView.swift`;
  orthographic toggle button; presets keyboarded (⌘⌥1…4).
- **Verify:** `ShopPilotVerify1206` — preset matrices, face→preset mapping,
  ortho vs perspective projection switch.
- **Files:** `Sources/ShopPilotCore/ViewOrientation.swift` (new),
  `ToolpathPreviewView.swift`, `ModelStageView.swift`, `Package.swift`.

#### SPK-1204 — Context menus everywhere
- **Engine:** `CommandContext` registry (Core): action + enabled predicate,
  so menu items share one source of truth with toolbars.
- **UI:** right-click menus on tree rows (Recalc / Move to Sheet / Delete),
  layers (Duplicate / Hide Empty), canvas (Draw / Transform / Paste), toolpath
  rows (via 1201 table).
- **Verify:** `ShopPilotVerify1204` — registry lookup + enabled-state
  derivation; sheet-transfer target validation.
- **Files:** `Sources/ShopPilotCore/CommandContext.swift` (new),
  `ToolpathTreeView.swift`, `ContentView.swift`, `Package.swift`.

### Wave 2 — the big two + guidance

#### SPK-1201 — Cut-Layers table (LightBurn-style)
- **Engine:** `CutLayerRow` model (Core): strategy, name, tool, feed,
  depth/pass, est. time, status (from 1207), enabled, order — aggregated from
  `ToolpathTree` in tree order; inline-edit commit routes to the existing
  `applyXParams` session methods; drag-reorder rewrites tree order.
- **UI:** replace the tree's flat section in the Cut left pane with a sortable
  grid (columns: ✓ | status | # | name | tool | feed | depth | time); inline
  TextFields; row drag; hover → highlight on canvas (feeds 1210).
- **Verify:** `ShopPilotVerify1201` — aggregation order, inline-edit commit
  mutates the right params, reorder persists to the tree, status column
  reflects 1207.
- **Files:** `Sources/ShopPilotCore/CutLayerTable.swift` (new),
  `ToolpathTreeView.swift` or `CutLayersTableView.swift` (new),
  `ContentView.swift`, `Package.swift`.

#### SPK-1202 — Surface-color material preview
- **Engine:** `MaterialSurfacePalette` (Core): material presets (walnut,
  acrylic, painted MDF, plywood) each with topColor/baseColor/layerCount;
  `shade(cutDepth, maxDepth, palette)` → color for the sim's heightfield
  renderer (top skin color until the cut passes the layer, then base).
- **UI:** material picker in `ToolpathPreviewView.swift` sim controls;
  renderer tints the heightfield by depth vs palette.
- **Verify:** `ShopPilotVerify1202` — shade at 0/25/75/100% depth,
  laminated-layer thresholds, preset round-trip.
- **Files:** `Sources/ShopPilotCore/MaterialSurfacePalette.swift` (new),
  `ToolpathPreviewView.swift`, `Package.swift`.

#### SPK-1205 — Inline coach strip
- **Engine:** `CoachRuleEngine` (Core): rules keyed on stage + selection +
  dirty + preflight state → tip string; priority ordering (blocking issue >
  empty state > suggestion).
- **UI:** hint strip under the stage rail (replaces static intent text when a
  rule fires); first-run tooltips (UserDefaults flag) walking the six stages.
- **Verify:** `ShopPilotVerify1205` — rule resolution matrix, priority
  ordering, no-tip fallback.
- **Files:** `Sources/ShopPilotCore/CoachRuleEngine.swift` (new),
  `ContentView.swift`, `StageEnum.swift`, `Package.swift`.

### Wave 3 — canvas ergonomics & production ops

#### SPK-1203 — Smart part selection + canvas dimension handles
- **Engine:** `PartDetector` (Geometry): closed shapes sharing an edge point
  (within tolerance) → one part; `DimensionHandle` model (anchor, offset,
  caption, drag→value math) over driven dimensions (SPK-0807).
- **UI:** Design canvas click → select whole part; driven-dimension rows get
  drag handles on canvas; value updates commit to the dimension + regenerates
  dependents.
- **Verify:** `ShopPilotVerify1203` — part detection on touching/overlapping
  squares, tolerance edges, handle drag math (anchor/offset/caption),
  dimension commit.
- **Files:** `Sources/ShopPilotGeometry/PartDetector.swift` (new),
  `Sources/ShopPilotCore/DimensionHandle.swift` (new), DesignStageView canvas,
  `Package.swift`.

#### SPK-1208 — Sheet duplication + toolpath sheet transfer
- **Engine:** `SheetOperations` (Core): `duplicateSheet(job, id)` deep-copies
  sheet + its vectors + toolpaths (new UUIDs, same names); `moveToolpath`
  re-parents a node to another sheet's group with sheet-consistency checks.
- **UI:** right-click (via 1204) + Setup-stage sheet row buttons
  (Duplicate / Delete); tree context "Move to Sheet → picker".
- **Verify:** `ShopPilotVerify1208` — deep-copy integrity (counts + new IDs),
  move across sheets keeps tree order, guard: can't move into itself.
- **Files:** `Sources/ShopPilotCore/SheetOperations.swift` (new),
  `SheetListView.swift`, `ToolpathTreeView.swift`, `Package.swift`.

#### SPK-1210 — Peck-drill viz + toolpath-on-hover
- **Engine:** extend wireframe renderer (`WireframeRenderer`) with peck-cycle
  motion detection (rapid retract within a drill block → peck retract lines)
  and per-node segment tagging (node id → segment indices).
- **UI:** sim draws peck retracts as dashed segments; hovering a tree/table
  row highlights that node's segments on the Preview canvas.
- **Verify:** `ShopPilotVerify1210` — peck detection on a peck G-code block,
  per-node segment tagging, hover lookup.
- **Files:** `Sources/ShopPilotCore/WireframeRenderer.swift`,
  `ToolpathPreviewView.swift`, `ToolpathTreeView.swift`, `Package.swift`.

## 3. Build order & dependencies

```
Wave 1: 1207 ─┐
        1209   │  (independent — parallelizable)
        1206   │
        1204 ──┤
Wave 2: 1201 (needs 1207) · 1202 · 1205
Wave 3: 1203 · 1208 (needs 1204) · 1210 (needs 1201 + renderer)
```

Each card: one commit (+ verify CLT registered in Package.swift), then the
whole-package build + full sweep at wave end. Board rows added under a new
`# PHASE L — UX overhaul (v2.1)` section; each `[x]` carries the CLT name.

## 4. Out of scope (intentionally)

- 3D-view editing (Aspire's node-edit-in-3D) — big engine lift, defer.
- 3D text — defer (2D text + relief path exists).
- Acceleration-aware time estimation — needs per-controller accel profiles,
  defer to machine-profiles wave.
- Easy/expert product split — progressive disclosure already chosen.

# Tool DB Seed Spec — loadable schema for SPK-1146 / SPK-1133

**Date:** 2026-08-05 · **Input:** `BIT_FEEDS_LIBRARY.md` (seed values, sources cited per row). **Purpose:** exact schema + values Hermes can load for the Tool DB seed without re-interpreting research. No Swift wiring here (build waves own that).
**Data model (from the incumbent research, 0FkoKHrktJE):** one tool **geometry** row × many **cutting_data** rows (per material+machine). A tool with no cutting_data for the active material+machine is **grayed out** in the picker (the incumbent UX, verified).

## 1. Schema

### tools (geometry — immutable per physical tool)

```json
{
  "id": "1-4in-2fl-upcut",
  "name": "1/4\" upcut end mill",
  "type": "endmill",                    // endmill | ballnose | vbit | drill | surfacing
  "diameter_inch": 0.25,                // nominal cutting diameter
  "flutes": 2,
  "shank_inch": 0.25,                   // optional, defaults = diameter
  "angle_deg": null,                    // vbit only (60/90); null otherwise
  "tip_diameter_inch": null,            // vbit flat-tip (for overcut calc); null = sharp
  "notes": "Onsrud 52-910 class; upcut for chip evacuation",
  "source": "onsrud-shopbot"            // citation key, see §3
}
```

### cutting_data (per material × machine — the grayed-out matrix)

```json
{
  "toolId": "1-4in-2fl-upcut",
  "materialKey": "hardwood",            // softwood | hardwood | plywood | mdf | acrylic
  "machineKey": "grbl-generic",         // machine profile key; "grbl-generic" = default
  "spindleRpm": 18000,
  "feedMmMin": 1500,
  "plungeMmMin": 600,                   // derived: ~40% of feed unless cited
  "passDepthMm": 2.0,                   // DOC per pass (1×D rule; start ≤ 50% diameter)
  "stepoverPct": 40,                    // 40 rough / 10-20 finish
  "source": "craftgineer-2026",
  "status": "seed"                      // seed = starting point, test-cut required
}
```

**CSV equivalent** (for a flat loader — same columns, one row per material):

```csv
toolId,name,type,diameter_inch,flutes,angle_deg,materialKey,spindleRpm,feedMmMin,plungeMmMin,passDepthMm,stepoverPct,source,status
1-4in-2fl-upcut,1/4" upcut end mill,endmill,0.25,2,,softwood,18000,2000,800,3.0,40,craftgineer-2026,seed
```

Notes:
- `machineKey` defaults to `grbl-generic`; per-machine rows (e.g. `onefinity`, `shapeoko`) may override feeds if a source cites them (none in this seed — all rows are generic).
- Units are SI internally (mm/min, mm); inch diameters converted (0.25″ = 6.35 mm) — app display converts back.
- `status: seed` rows must be flagged in UI ("starting point — test-cut required"), matching every cited source's warning.

## 2. The 7×5 starter matrix (values)

Tools (geometry): T1 1/4″ upcut 2-flute endmill · T2 1/4″ downcut 2-flute endmill · T3 1/8″ 2-flute endmill · T4 1/8″ 2-flute ballnose · T5 60° V-bit (1/2″ dia) · T6 90° V-bit (1/2″ dia) · T7 1/4″ drill.

Materials: softwood · hardwood · plywood · mdf · acrylic.

### Feed (mm/min) — primary number
| Tool | softwood | hardwood | plywood | mdf | acrylic | source |
|---|---|---|---|---|---|---|
| T1 1/4″ upcut | 2000 | 1500 | 1500 | 1800 | 1200 | craftgineer-2026 (acrylic @16k RPM, cast) |
| T2 1/4″ downcut | 2000 | 1500 | 1500 | 1800 | 1200 | same as T1 (downcut feed ≈ upcut; ShopBot 57-910 vs 52-910 both .006–.009) |
| T3 1/8″ endmill | 1200 | 1000 | 1000 | 1200 | 800 | craftgineer-2026 (20k RPM) |
| T4 1/8″ ballnose | 1500 | 1200 | 1200 | 1500 | 900 | derived from Onsrud 77-102 chip load (.003–.005″/edge @18k) |
| T5 60° V-bit | 1500 | 1200 | 1200 | 1500 | 900 | craftgineer-2026; Onsrud 37-82 (.004–.006″/edge) |
| T6 90° V-bit | 1800 | 1400 | 1400 | 1800 | 1100 | craftgineer-2026 (90° DOC 4.0/3.0/4.0) |
| T7 1/4″ drill | 300 | 250 | 250 | 300 | 200 | conservative (peck drilling not in seed; plunge-dominant) |

### Spindle (RPM)
| Tool | softwood | hardwood | plywood | mdf | acrylic | source |
|---|---|---|---|---|---|---|
| T1/T2 | 18000 | 18000 | 18000 | 18000 | 16000 | craftgineer-2026 (acrylic 16k = less heat) |
| T3 | 20000 | 20000 | 20000 | 20000 | 18000 | craftgineer-2026 |
| T4 | 18000 | 18000 | 18000 | 18000 | 16000 | Onsrud 77-102 @18k base |
| T5/T6 | 18000 | 18000 | 18000 | 18000 | 16000 | craftgineer-2026 / ShopBot 18k base |
| T7 | 12000 | 12000 | 12000 | 12000 | 12000 | drill default (no cited source — conservative) |

### Pass depth (mm, DOC per pass)
| Tool | softwood | hardwood | plywood | mdf | acrylic | source |
|---|---|---|---|---|---|---|
| T1 | 3.0 | 2.0 | 2.5 | 2.5 | 2.0 | craftgineer-2026 |
| T2 | 3.0 | 2.0 | 2.5 | 2.5 | 2.0 | same as T1 |
| T3 | 1.5 | 1.0 | 1.0 | 1.5 | 1.0 | craftgineer-2026 (1/8″ ≈ half rigidity) |
| T4 | 1.5 | 1.0 | 1.0 | 1.5 | 1.0 | 1×D rule for 1/8″ (77-102 cut 1×D) |
| T5 | 3.0 | 2.5 | 2.5 | 3.0 | 2.0 | craftgineer-2026 (60° max DOC) |
| T6 | 4.0 | 3.0 | 3.0 | 4.0 | 2.5 | craftgineer-2026 (90° max DOC) |
| T7 | 19.0 | 19.0 | 19.0 | 19.0 | 19.0 | through-hole default = material thickness cap; drill uses plunge not DOC |

### Stepover (% of diameter) — all tools
| Tool | softwood | hardwood | plywood | mdf | acrylic | source |
|---|---|---|---|---|---|---|
| T1/T2/T3 | 40 | 40 | 40 | 40 | 40 | craftgineer-2026 (rough 40–50; finish 10–20) |
| T4 ballnose | 10 (finish) | 10 | 10 | 10 | 10 | 3D finishing video NF9oaCjXmAo: finish stepover 8–12% |
| T5/T6 V-bit | 40 | 40 | 40 | 40 | 40 | V-carve uses toolpath geometry, not stepover — unused but set |
| T7 drill | 0 | 0 | 0 | 0 | 0 | not a milling operation |

### Plunge (mm/min) — derived where uncited
| Tool | softwood | hardwood | plywood | mdf | acrylic | source |
|---|---|---|---|---|---|---|
| T1/T2 | 800 | 600 | 600 | 720 | 480 | ~40% of feed (derived; test-cut) |
| T3 | 480 | 400 | 400 | 480 | 320 | ~40% of feed (derived) |
| T4 | 600 | 480 | 480 | 600 | 360 | ~40% of feed (derived) |
| T5/T6 | 600 | 480 | 480 | 600 | 360 | ~40% of feed (derived) |
| T7 | 150 | 120 | 120 | 150 | 100 | drill plunge-dominant; 50% of feed |

## 3. Source citation keys

| Key | Reference | Notes |
|---|---|---|
| `onsrud-shopbot` | ShopBot "Feeds and Speeds Charts" (Onsrud series data, 18,000 RPM base, PDF) | chip load per leading edge; used for ballnose/V-bit feeds |
| `craftgineer-2026` | Craftgineer CNC Feeds & Speeds for Beginners (starter tables) | exact RPM/feed/DOC/stepover rows; mid-range hobby machine class |
| `onefinity-forum` | Onefinity forum beginner guidance (40–60 ipm, DOC 50% dia) | sanity check, not seeded |
| `toolstoday` | Toolstoday chip-load primer (formula) | formula, not values |
| `derived` | computed from cited chip loads or 40% rule | marked `status: seed` + flag in UI |
| `grbl-matrix` | GRBL_DIALECT_MATRIX.md (`$110–$112` machine max-rate clamp) | clamp feed ≤ machine max at post time |

## 4. Grayed-out UX (from the incumbent research, 0FkoKHrktJE + tmaTxrZZv6Y)

- Tool is **grayed out** in the picker when `cutting_data` has no row for (materialKey, machineKey).
- Right panel shows geometry (diameter/flutes/angle — unchanged) but no feeds/speeds; an "Add feeds & speeds" action copies from another material or opens the editor (the incumbent's `copy settings from`).
- `hide unset tools` toggle to declutter (the incumbent right-click option).
- At toolpath creation time, if the selected tool is grayed out → inline prompt to add feeds/speeds (the incumbent: "there is an option to add the tool settings and feeds and speeds when creating toolpaths").
- Warn at calculate: chip load outside the material's target range and/or feed > machine max (`$110–$112`) — maps to R022/R008 in PREFLIGHT_FM_MAPPING.md.

## 5. Loader contract for build waves

- Loader accepts the JSON array (or CSV) above; seeds `tools` + `cutting_data` tables; marks all rows `status: seed`.
- Deterministic IDs (`1-4in-2fl-upcut`) so goldens and tests can reference tools by ID.
- Seed is idempotent: re-running upserts by (toolId, materialKey, machineKey).
- `machineKey: grbl-generic` is the fallback for any machine profile without specific rows.

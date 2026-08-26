# Bit / Feeds Library Research — ShopPilot cutting-data seed matrix (offline)

**Date:** 2026-08-04 · **Sources:** ShopBot "Feeds and Speeds Charts" (Onsrud-derived, PDF), Craftgineer starter tables, toolstoday chip-load primer, Onefinity forum guidance. All numeric data is *conservative starting points* — user must test-cut and tune (every source says exactly that).
**Purpose:** seed ShopPilot's offline Tool DB cutting-data matrix (LEAN_CNC_SCOPE P1: "Tool DB seed + feeds wired to recalc"). Model: one tool geometry × per-material cutting data (matches the incumbent's model from 0FkoKHrktJE).

---

## 1. The formula (what to implement, not just store)

```
Chip Load (mm/th/tooth) = Feed Rate (mm/min) / (RPM × Number of Flutes)
Feed Rate = Chip Load × RPM × Flutes
```

- **Chip load too small** → bit rubs → heat → dull bit, burned/melted material (plastics melt back onto bit).
- **Chip load too large** → chatter, deflection, snapped bit.
- Rule of thumb: **DOC ≤ bit diameter** (start at ~50% diameter for 2-flute; 1/8" bits take ~half the DOC of 1/4").
- **Stepover:** 40–50% roughing, 10–20% finishing.
- Hobby trim-router class: **16,000–24,000 RPM** for wood; plastics lower (16k, less heat); 18,000 is the universal default used by both ShopBot charts and Craftgineer.
- Machine limits cap the result: don't exceed the machine's max feed rate (`$110–$112` in GRBL) — ShopPilot should clamp cutting data against the machine profile.

## 2. Manufacturer chart — Onsrud via ShopBot (verified, 18,000 RPM base)

From ShopBot Feeds & Speeds PDF (Onsrud series numbers included for cross-ref):

| Tool | Onsrud Series | Chip load/edge (in) | Flutes | Feed @18k (in/min) | Materials |
|---|---|---|---|---|---|
| 1" 60° V-cutter | 37-82 | .004–.006 | 2 | 144–216 | softwood/hardwood/MDF/chipboard |
| 1/4" straight V end mill | 48-005 | .005–.007 | 1 | 90–126 | hardwood/MDF |
| 1/2" straight V end mill | 48-072 | .005–.010 (by material) | 2 | 180–324 | hardwood/MDF/chipboard |
| 1/4" upcut end mill | 52-910 | .006–.009 | 2 | 216–324 | softwood/hardwood/MDF |
| 1/4" downcut end mill | 57-910 | .005–.009 | 2 | 180–324 | softwood/hardwood/MDF |
| 1/4" upcut end mill (1-flute) | 65-025 | .004–.006 | 1 | 72–108 | all woods |
| 1/8" tapered upcut ball end mill | 77-102 | .003–.005 | 2 | 108–180 | all woods |
| 1-1/4" surfacing cutter | 91-000 | (feed 200–600 ipm) | 2 | 200–600 @ 12–16k | surfacing |

All cuts assumed 1×D depth of cut unless noted. Notable: **V-cutter chip loads are generous (.004–.006/edge)** — V-carving feeds are not the bottleneck; depth control is.

## 3. Hobby starter tables (Craftgineer — mid-range machines: Shapeoko/X-Carve/LongMill class)

### 1/4" (6.35mm) flat end mill, 2-flute
| Material | RPM | Feed (mm/min) | DOC (mm) | Stepover |
|---|---|---|---|---|
| Softwood | 18,000 | 2000 | 3.0 | 40% |
| Hardwood | 18,000 | 1500 | 2.0 | 40% |
| Plywood (birch) | 18,000 | 1500 | 2.5 | 40% |
| MDF | 18,000 | 1800 | 2.5 | 40% |
| Cast acrylic | 16,000 | 1200 | 2.0 | 40% |

### 1/8" (3.175mm) flat end mill, 2-flute
| Material | RPM | Feed (mm/min) | DOC (mm) | Stepover |
|---|---|---|---|---|
| Softwood | 20,000 | 1200 | 1.5 | 40% |
| Hardwood | 20,000 | 1000 | 1.0 | 40% |
| Plywood | 20,000 | 1000 | 1.0 | 40% |
| MDF | 20,000 | 1200 | 1.5 | 40% |
| Cast acrylic | 18,000 | 800 | 1.0 | 40% |

### 60° V-bit / 90° V-bit (max DOC)
| Material | 60° RPM/feed/DOC | 90° RPM/feed/DOC |
|---|---|---|
| Softwood | 18k / 1500 / 3.0mm | 18k / 1800 / 4.0mm |
| Hardwood | 18k / 1200 / 2.5mm | 18k / 1400 / 3.0mm |
| MDF | 18k / 1500 / 3.0mm | 18k / 1800 / 4.0mm |

### Ball nose (for 3D finish) — derived from chip-load tables (1/8" ball: .003–.005"/edge @ 18k → ~110–180 ipm)
| Material | RPM | Feed (mm/min) | DOC/stepover note |
|---|---|---|---|
| Softwood | 18,000 | 1500 | finish stepover 8–12% of dia |
| Hardwood | 18,000 | 1200 | finish stepover 8–12% |
| MDF | 18,000 | 1500 | finish stepover 8–12% |

## 4. Target chip loads by material (for a future in-app calculator)

| Material | Chip load (mm) | (in) | Notes |
|---|---|---|---|
| Softwood (pine/cedar/basswood) | 0.04–0.06 | .0015–.0025 | forgiving |
| Hardwood (maple/cherry/walnut) | 0.03–0.05 | .0012–.0020 | moderate |
| Plywood (baltic birch) | 0.03–0.05 | .0012–.0020 | glue tough on bits |
| MDF | 0.03–0.05 | .0012–.0020 | dusty, consistent |
| Cast acrylic | 0.05–0.08 | .0020–.0030 | single-flute recommended |
| Extruded acrylic | 0.04–0.06 | .0015–.0025 | melts easier |
| HDPE | 0.06–0.10 | .0025–.0040 | forgiving |
| PVC foam (Sintra) | 0.05–0.08 | .0020–.0030 | single flute |
| 6061 aluminum (hobby) | 0.02–0.04 | .001–.0015 | single-flute upcut + lube, shallow passes |

## 5. Common mistakes the sources warn about (→ preflight rules)

1. **RPM too low** — hobby routers are designed for high RPM/low chip load; 8,000 RPM "feels safer" but dulls bits and quadruples job time.
2. **Not scaling DOC to bit size** — 1/8" bit ≈ half the rigidity of 1/4"; halve DOC.
3. **Ignoring machine max feed** — formulas may say 3,000 mm/min but a 3018 loses steps; clamp to `$110–$112`.
4. **Same settings across materials** — pine ≠ maple; per-material cutting data is mandatory (the incumbent's model: same tool, different cutting data per material).
5. **Stepover too coarse on finish** — 10–20% finishing; witness marks (see 3D finishing video NF9oaCjXmAo).

## 6. Seed matrix recommendation (ShopPilot Tool DB v1)

Seed these tool geometries (fixed) with per-material cutting data (RPM/feed/plunge/DOC/stepover) for **Softwood, Hardwood, Plywood, MDF, Acrylic**:

- 1/4" 2-flute upcut end mill (Onsrud 52-910 class)
- 1/4" 2-flute downcut end mill (57-910 class)
- 1/8" 2-flute end mill
- 1/8" 2-flute ball nose (77-102 class)
- 60° V-bit (37-82 class, 1" — plus a common 1/2" 60° variant)
- 90° V-bit
- 1/4" drill bit (spot/drill; feeds modest)

Data model per tool: `diameter, flutes, type, angle (V-bit/ball), notes`; per (material): `spindle_rpm, feed_rate, plunge_rate, pass_depth, stepover_pct`. Seed values = conservative midpoints from §2–§3, flagged `source: Onsrud-SB|crafteginer`, `status: seed — test-cut required`. Show a "derived from chip load" calculator in-app later; v1 just stores the matrix.

Raw notes saved under `research/raw/` (gitignored); this summary is the planning artifact. All values are starting points, not guarantees — the app must say so (matching the incumbent's own guidance: "test cuts on your material first").

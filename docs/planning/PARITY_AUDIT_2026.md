# ShopPilot ↔ VectorPilot Parity Audit — 2026-08-24

**Reference:** VectorPilot `origin/main@e954552` (Wave P complete, board empty)
**ShopPilot:** `master@HEAD` with Phase V parity wave (SPK-2000a–d)
**Directive:** both apps ship the same day; features must MATCH.

## Feature surface

| Area | VectorPilot | ShopPilot before | ShopPilot now | Status |
|---|---|---|---|---|
| Toolpath strategies | 29 in registry | 21 + trochoid | unchanged (Mac leads: Trochoid Slot) | ✅ superset |
| Post-processors | 54 shipped | 3 | **55** (SPK-2000a) | ✅ |
| Laser cut/fill/picture | ✅ | vector cut/engrave only | **+ Fill + Picture engines, More-menu, laser posts** (2000c) | ✅ |
| Cabinetry import | 6 vendor CSVs | none | **+ CabinetryImporter, 6 dialects, Import Hub row** (2000b) | ✅ |
| Shaded 3D relief view | WPF Viewport3D mesh | 2.5D heightmap orbit | **+ ReliefMeshEngine lambert mesh + GPU-perspective orbit** (2000d) | ✅ (2.5D projection — honest note below) |
| Offline preview playhead | ❌ (live-stream cursor only) | SPK-1700 playhead | unchanged | ✅ Mac leads |
| Plugins / scripting | Lua host (MoonSharp) | Plugin ABI (child-process sandbox) | unchanged | ✅ equivalent-by-design (documented deferral: no Lua on Mac) |
| Beginner/Advanced mode | H-101 | SPK-1900c | — | ✅ parity |
| Frame job + click-to-jog | H-104 | SPK-1900b | — | ✅ parity |
| Wasteboard surfacing | H-402 wizard | SPK-1920g | — | ✅ parity |
| Touch probe | H-401 | G38.2 touch-off | — | ✅ parity |
| Material presets → Cut | H-501 | tool DB catalogs | — | ✅ parity |
| Inverse mill | H-304 | SPK-1920d | — | ✅ parity |
| Dual-sided export | P-301 | multi-sheet/double-sided jobs | — | ✅ parity |
| V-carve flat clearing | P-202 | clearance-tool pass | — | ✅ parity |
| Nesting wired to UI | P-101-era + Design | SPK-1900f | — | ✅ parity |
| Live stream playhead | H-503 | SPK-1920h | — | ✅ parity |
| Dogfood hardening (console windowing, chrome guard, stale-transport teardown) | ❌ | DOGFOOD-01…05 | unchanged | ✅ Mac leads |

## Honest remaining differences

1. **3D preview depth**: VectorPilot's Viewport3D is a true orbitable shaded mesh;
   ShopPilot's is a perspective-projected heightmap with directional shadow
   (GPU-backed rotation3DEffect) plus the CLT-proven `ReliefMeshEngine` for the
   mesh data. Same information, different rendering fidelity.
2. **Scripting host**: Mac uses its own plugin ABI (child process, JSON contract)
   rather than Lua. Both are sandboxed extensibility; neither runs the other's scripts.
3. **Laser hardware claims**: both apps' laser paths are engine+UI verified but
   untested against real laser hardware (no device on either machine).

## Verification

| Gate | Result |
|---|---|
| `ShopPilotVerify2000a` | PASS — 55 templates emit clean, units distinct, groups total |
| `ShopPilotVerify2000b` | PASS — six dialects parse, geometry fits/no-overlap, honest failures |
| `ShopPilotVerify2000cLaser` | PASS — fill coverage/serpentine, picture power modulation, zero-ALARM stream |
| `ShopPilotVerify2000d` | PASS — mesh counts/normals/shading/downsample/degenerate |
| Full shakedown sweep | re-run at close-out (see `results/CLTS.md`) |

**SPK-0623 remains `[ ]` — owner decision. This audit does not stamp ship.**

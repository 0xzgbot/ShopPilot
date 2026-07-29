# ShopPilot — Product Boundaries

**Date:** 2026-07-28  
**Working name:** ShopPilot  
**Status:** Living boundary document — update when scope decisions change.

---

## What ShopPilot Is

- **Relief CAM software.** ShopPilot generates CNC toolpaths from pre-existing 3D mesh models (relief sculptures, bas-reliefs). It is a CAM *toolpath generator and machine controller*, not a general-purpose CAD suite.
- **Mesh-first geometry.** Input formats are STL and OBJ — triangle-mesh files produced by sculpting tools, photogrammetry pipelines, or other 3D modeling software. ShopPilot reads these meshes, computes toolpaths over their surfaces, and outputs G-code for CNC routers.
- **macOS-native CNC suite.** Built with SwiftUI (macOS 14+), targeting Apple Silicon first. Includes machine control (GRBL/FluidNC serial communication) alongside the CAM studio.

## What ShopPilot Is NOT

- **NOT full solid CAD.** ShopPilot does not replace Fusion 360, SolidWorks, Rhino, or FreeCAD. It does not provide parametric solid modeling, sketch-based feature operations, B-rep geometry kernels, or assembly management.
- **NOT a parametric modeler.** There is no CSG (constructive solid geometry), no NURBS surface editor, no parametric constraint solver. If you need to design a part from scratch with dimensions and constraints, use a proper CAD tool first — then export STL/OBJ for ShopPilot.
- **NOT a vector-only 2D design suite.** While basic 2D toolpaths (profile, pocket) are included, ShopPilot is not a replacement for dedicated 2D CAD/vector tools like Illustrator or Inkscape for pure graphic design work.

## Geometry & Import Boundaries

| Supported | Not supported |
|---|---|
| STL (binary + ASCII) | STEP / IGES / Parasolid |
| OBJ (with .mtl material refs) | SolidWorks `.sldprt` / `.sldasm` |
| Mesh normals, vertex positions, face indices | Parametric feature trees |
| Basic mesh repair (weld, flip normals, remove degenerate faces) | Boolean operations on solids |
| Relief depth analysis & toolpath mapping over surfaces | Full assembly management |

## Safety Constraints (from SAFETY.md)

- **No Vectric proprietary assets.** ShopPilot never uses, imports, reverse-engineers, or bundles Vectric's `.CRV` project files, `.VEE` vector libraries, `.SPR` shape packs, or any other Vectric-proprietary format. This is a legal boundary — not just a technical one.
- **Independent implementation only.** All toolpath algorithms are implemented from first principles and public G-code specifications (GRBL protocol, EIA/RS-274-D). No decompiled code, no proprietary parsers.
- **Software is not a substitute for hardware e-stop.** The product includes safety interlocks in software, but the operator must always have a physical emergency stop within reach.

## Scope Change Protocol

Any decision to expand ShopPilot's geometry engine (e.g., adding STEP import, parametric sketching) requires:
1. A new card on `MASTER_KANBAN.md` with explicit AC and risk assessment.
2. Re-evaluation of the "Not in first ship" list in AGENTS.md.
3. Legal review if any proprietary format is considered for import support.

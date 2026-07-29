# ShopPilot — 3D Relief Model Import (STL/OBJ)

**Date:** 2026-07-28  
**Purpose:** Define the file import system for 3D relief geometry.

---

## Overview

ShopPilot needs to import 3D mesh models that represent relief artwork (portraits, decorative patterns, etc.). The two primary formats are STL and OBJ — both widely supported by CAD software, 3D scanners, and sculpting tools.

---

## Format Specifications

### STL (Stereolithography)

#### Binary STL (Preferred)
- **Structure:** 80-byte header + 4-byte triangle count + N triangles
- **Each triangle:** 12 floats (normal vector × 3 components per vertex × 3 vertices = 9 floats, but normal is shared: 3 + 12 = 15 floats = 60 bytes)
- **Total size:** 84 + (50 × N) bytes
- **Advantages:** Smaller file size (~2/3 of ASCII), faster parsing

#### ASCII STL
- Same logical structure but human-readable text format
- Each triangle: `facet normal nx ny nz` → `outer loop` → 3× `vertex x y z` → `endloop` → `endfacet`
- **Advantages:** Easy to debug, can be opened in a text editor

#### ShopPilot Support
- Parse binary STL by default (detect via magic bytes check)
- Fall back to ASCII parser if binary header doesn't match expected structure
- No material/color data — STL is geometry-only

### OBJ (Wavefront Object)

#### Structure
```
# Comment line
v 10.0 20.0 30.0        # vertex position
vn 0.0 1.0 0.0          # vertex normal
vt 0.5 0.5              # texture coordinate (unused for CNC)
f 1/1/1 2/2/2 3/3/3     # face (vertex/normal indices, 1-based)
```

#### Key Features
- Supports triangulated faces (`f`) and polygonal faces (`f` with >3 vertices)
- Optional material library (.mtl file in same directory) — not used for CNC but should be gracefully ignored
- Can reference external geometry files via `usemtl` — ignore for ShopPilot

#### ShopPilot Support
- Parse OBJ text format (no binary OBJ exists as a standard)
- Triangulate polygonal faces automatically (fan triangulation from first vertex)
- Ignore texture coordinates and material data
- Read normals if present; compute flat normals if absent

---

## Coordinate System Mapping

### Source Format Conventions

| Format | Axis Convention | Right-handed? |
|---|---|---|
| STL (typical CAD export) | Y-up or Z-up depending on source software | Usually yes |
| OBJ | Varies by exporter; Maya uses Y-up, Blender uses Z-up | Depends |

### ShopPilot Coordinate System

ShopPilot uses a **Z-up** coordinate system consistent with CNC machine conventions:
- **X:** Left-to-right (width direction)
- **Y:** Front-to-back (depth direction)  
- **Z:** Bottom-to-top (height/thickness direction)

### Mapping Strategy

```
STL/OBJ (may be Y-up or Z-up) → Detect orientation → Convert to ShopPilot Z-up
```

#### Detection Heuristic

1. **Compute bounding box** of the mesh in source coordinates
2. **Analyze aspect ratios:** If one dimension is significantly smaller (< 5% of max), that's likely the Z-axis (thickness direction for a relief)
3. **Check face normals:** For a relief, most normals should point roughly "up" — determine which axis this aligns with in source coordinates
4. **Apply transform:** Rotate/flip so that:
   - Source "up" → ShopPilot +Z
   - Source X/Y → ShopPilot X/Y (preserving handedness)

#### Explicit User Override

The import dialog includes a "Orientation" selector:
- Auto-detect (default, uses heuristic above)
- Y-up source (common from Maya/Blender)
- Z-up source (common from CAD exports)
- Manual rotation (0°, 90°, 180°, 270° around any axis)

---

## Mesh Simplification Strategy

### Why Simplify?

Raw STL/OBJ files from sculpting software can contain millions of triangles. For CNC toolpath generation:
- Full-resolution meshes are unnecessary — surface detail at the micron level doesn't affect toolpaths
- Processing time scales with triangle count (O(n) for contour extraction, O(n²) for some algorithms)
- Memory usage matters on lower-end Macs

### Simplification Algorithm

**Quadric Error Metric (QEM)** — Garland & Heckbert 1997:
- Iteratively collapses edges that add least visual error
- Preserves sharp features better than Laplacian smoothing
- Well-documented, open-source implementations available

### Target Triangle Counts

| Use Case | Source Resolution | Simplified Target | Reduction |
|---|---|---|---|
| Portrait relief (4" × 6") | 1–5M triangles | 50K–200K triangles | 95–99% |
| Decorative pattern (small) | 500K–2M triangles | 30K–80K triangles | 90–97% |
| Large architectural element | 10M+ triangles | 500K–1M triangles | 90–95% |

### UI Implementation

The import dialog includes a "Detail level" slider:
- **Maximum (no simplification):** Keep all triangles — for very small models or when user wants maximum fidelity
- **High:** Target ~200K triangles — good balance of quality and performance
- **Medium (default):** Target ~80K triangles — sufficient for most CNC applications
- **Low:** Target ~30K triangles — fast preview, may lose fine detail

Show estimated triangle count and file size after simplification before confirming import.

---

## Error Handling

### File-Level Errors

| Error | Cause | User Message |
|---|---|---|
| File not found / unreadable | Corrupted download, wrong path | "Cannot read file — it may be corrupted or in use by another application." |
| Invalid STL header | Not actually an STL file | "This file does not appear to be a valid STL file. Please check the format." |
| Incomplete binary STL | Truncated write during export | "STL file is incomplete — expected N triangles but found only M. The file may have been corrupted during export." |
| OBJ references missing .mtl | Material library not bundled | Warning (non-fatal): "Associated material file not found. Geometry will be imported without materials." |

### Mesh-Level Errors

| Error | Cause | User Message |
|---|---|---|
| Non-manifold geometry | Edges shared by >2 faces | "The model contains non-manifold edges (edges shared by more than two faces). These areas may not import correctly. Continue anyway?" |
| Degenerate triangles | Zero-area or duplicate vertices | "The model contains degenerate (zero-area) triangles. These have been removed during import." |
| Self-intersecting mesh | Overlapping geometry | "The model appears to self-intersect. Toolpath generation may produce unexpected results in overlapping regions." |
| Extremely large bounding box | Wrong scale (e.g., mm vs inches confusion) | Warning: "This model's dimensions are unusually large ({width}×{depth}mm). Did you intend a different unit?" |

### Recovery Strategies

1. **Auto-fix degenerate geometry:** Remove zero-area triangles, merge duplicate vertices within tolerance
2. **Warn on non-manifold edges:** Don't block import — let the user proceed with awareness
3. **Scale detection:** If bounding box exceeds 500mm in any dimension, show a scale warning (common when importing inch-based models into mm workspace)

---

## Integration with Stage System

### Import Flow

1. **Setup stage:** User clicks "Import 3D Model" → file picker opens
2. **Preview:** Model appears in the 3D preview pane with bounding box overlay
3. **Configuration:** Orientation and simplification settings dialog
4. **Confirmation:** User confirms, model is loaded into the document's sheet geometry

### Document Model Integration

The imported mesh becomes part of `Sheet.geometry`:

```swift
struct SheetGeometry {
    let mesh: MeshData          // Simplified triangle mesh
    let stockDimensions: Size3D // Width × Depth × Height in mm
    let originOffset: Point3D   // Where (0,0,0) maps to on the sheet
}
```

### Undo Support

Import is a single undoable operation — `DirtyDocument` marks the document dirty when import completes. User can undo to return to pre-import state.

---

## Supported File Extensions

| Extension | Format | Notes |
|---|---|---|
| `.stl` | Binary or ASCII STL | Primary format for 3D relief geometry |
| `.obj` | Wavefront OBJ | Secondary format, supports polygonal faces |
| `.ply` | (Future) | Point cloud / mesh format — not in v1.0 scope |

---

## Notes

- All format specifications described here are from open standards (STL spec by 3D Systems, OBJ spec by Wavefront Technologies)
- QEM simplification algorithm is published academic work (Garland & Heckbert, 1997)
- No Vectric proprietary assets or algorithms used

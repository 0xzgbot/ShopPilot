#!/usr/bin/env python3
"""Generate the complex import/export test pack for ShopPilot.

Files (all in fixtures/testpack/):
  complex_artwork.svg  — every SVG primitive the importer handles, nested
                         transforms, groups, text-ish paths, mixed open/closed
  complex_plate.dxf    — R12 DXF: LWPOLYLINE, LINE, CIRCLE, ARC, multiple
                         layers, a pocket profile + drill points
  terrain_mesh.stl     — a real 3D heightfield terrain (a few thousand
                         triangles) for 3D rough/finish/rest machining
  testpack.README.md   — what each file exercises
"""
import math
import os
import random
import struct

random.seed(20260811)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures", "testpack")
os.makedirs(OUT, exist_ok=True)


# ── 1. complex_artwork.svg ────────────────────────────────────────────────
def make_svg() -> str:
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="400mm" height="300mm" viewBox="0 0 400 300">',
        '  <g id="artwork" transform="translate(10,10)">',
        # rects (open shape set)
        '    <rect x="20" y="20" width="120" height="80" fill="none" stroke="#000"/>',
        '    <rect x="30" y="120" width="200" height="100" rx="8" ry="8" fill="none" stroke="#000"/>',
        # circles + ellipse
        '    <circle cx="200" cy="200" r="40" fill="none" stroke="#000"/>',
        '    <circle cx="240" cy="60" r="12" fill="none" stroke="#000"/>',
        '    <ellipse cx="300" cy="220" rx="45" ry="20" fill="none" stroke="#000"/>',
        # lines
        '    <line x1="20" y1="20" x2="140" y2="100" stroke="#000"/>',
        '    <line x1="160" y1="20" x2="160" y2="140" stroke="#000"/>',
        # polylines (open)
        '    <polyline points="60,220 90,200 120,225 150,205 180,230" fill="none" stroke="#000"/>',
        # polygons (closed)
        '    <polygon points="280,20 320,20 340,60 300,80 260,60" fill="none" stroke="#000"/>',
        '    <polygon points="20,240 50,280 90,270 70,235" fill="none" stroke="#000"/>',
        # paths: closed rect-ish, bezier open curve, arc-ish
        '    <path d="M 200,260 L 240,260 L 240,290 L 200,290 Z" fill="none" stroke="#000"/>',
        '    <path d="M 320,140 C 340,180 300,200 340,240" fill="none" stroke="#000"/>',
        '    <path d="M 250,100 Q 270,70 290,100 T 330,100" fill="none" stroke="#000"/>',
        # nested group with its own transform
        '    <g transform="translate(150,0) scale(0.6)">',
        '      <circle cx="40" cy="200" r="30" fill="none" stroke="#000"/>',
        '      <rect x="0" y="160" width="80" height="20" fill="none" stroke="#000"/>',
        '    </g>',
        '  </g>',
        '</svg>',
    ]
    return "\n".join(parts) + "\n"


# ── 2. complex_plate.dxf (R12, mm) ────────────────────────────────────────
def dxf_pair(code: int, value) -> str:
    return f"{code}\n{value}\n"


def make_dxf() -> str:
    out = []
    # HEADER: INSUNITS=4 (mm)
    out.append("0\nSECTION\n2\nHEADER\n")
    out.append(dxf_pair(9, "$INSUNITS") + dxf_pair(70, 4))
    out.append("0\nENDSEC\n")
    # TABLES: layers
    out.append("0\nSECTION\n2\nTABLES\n")
    for name, color in [("OUTLINE", 1), ("POCKET", 5), ("DRILL", 3), ("DECOR", 2)]:
        out.append("0\nTABLE\n2\nLAYER\n70\n4\n")
        out.append("0\nLAYER\n2\n" + name + "\n70\n0\n62\n" + str(color) + "\n6\nCONTINUOUS\n")
        out.append("0\nENDTAB\n")
    out.append("0\nENDSEC\n")
    # ENTITIES
    out.append("0\nSECTION\n2\nENTITIES\n")
    # Outer pocket boundary (LWPOLYLINE closed, layer POCKET)
    out.append("0\nLWPOLYLINE\n8\nPOCKET\n90\n4\n70\n1\n")
    for x, y in [(40, 40), (240, 40), (240, 140), (40, 140)]:
        out.append(dxf_pair(10, x) + dxf_pair(20, y))
    # A few lines (OUTLINE)
    for x1, y1, x2, y2 in [(10, 10, 270, 10), (10, 170, 270, 170), (10, 10, 10, 170), (270, 10, 270, 170)]:
        out.append("0\nLINE\n8\nOUTLINE\n" + dxf_pair(10, x1) + dxf_pair(20, y1) + dxf_pair(11, x2) + dxf_pair(21, y2))
    # Circles (DECOR)
    out.append("0\nCIRCLE\n8\nDECOR\n" + dxf_pair(10, 300) + dxf_pair(20, 60) + dxf_pair(40, 25))
    out.append("0\nCIRCLE\n8\nDECOR\n" + dxf_pair(10, 300) + dxf_pair(20, 120) + dxf_pair(40, 15))
    # Arcs (DECOR)
    out.append("0\nARC\n8\nDECOR\n" + dxf_pair(10, 300) + dxf_pair(20, 200) + dxf_pair(40, 30)
               + dxf_pair(50, 30) + dxf_pair(51, 150))
    out.append("0\nARC\n8\nDECOR\n" + dxf_pair(10, 200) + dxf_pair(20, 220) + dxf_pair(40, 20)
               + dxf_pair(50, 180) + dxf_pair(51, 360))
    # Drill points (DRILL) — 5 circles
    for i in range(5):
        out.append("0\nCIRCLE\n8\nDRILL\n" + dxf_pair(10, 60 + i * 30) + dxf_pair(20, 60) + dxf_pair(40, 3))
    out.append("0\nENDSEC\n0\nEOF\n")
    return "".join(out)


# ── 3. terrain_mesh.stl (ASCII) ───────────────────────────────────────────
def make_stl() -> str:
    """Procedural terrain heightfield: 60x40 grid → ~4,800 triangles."""
    nx, ny = 60, 40
    w, d = 120.0, 80.0
    heights = {}
    for ix in range(nx + 1):
        for iy in range(ny + 1):
            x = ix / nx * w
            y = iy / ny * d
            # Two overlapping gaussian hills + noise.
            h = (6.0 * math.exp(-((x - 40) ** 2 + (y - 20) ** 2) / 300)
                 + 4.5 * math.exp(-((x - 85) ** 2 + (y - 60) ** 2) / 200)
                 + 1.2 * math.sin(x / 9.0) * math.cos(y / 7.0))
            heights[(ix, iy)] = max(0.0, h)

    def v(ix, iy):
        x = ix / nx * w
        y = iy / ny * d
        return (x, y, heights[(ix, iy)])

    def normal(a, b, c):
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        nx = uy * vz - uz * vy
        ny = uz * vx - ux * vz
        nz = ux * vy - uy * vx
        L = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        return (nx / L, ny / L, nz / L)

    lines = ["solid terrain"]
    for ix in range(nx):
        for iy in range(ny):
            a = v(ix, iy)
            b = v(ix + 1, iy)
            c = v(ix + 1, iy + 1)
            dpt = v(ix, iy + 1)
            for tri in [(a, b, c), (a, c, dpt)]:
                n = normal(*tri)
                lines.append(f"  facet normal {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}")
                lines.append("    outer loop")
                for p in tri:
                    lines.append(f"      vertex {p[0]:.4f} {p[1]:.4f} {p[2]:.4f}")
                lines.append("    endloop")
                lines.append("  endfacet")
    lines.append("endsolid terrain")
    return "\n".join(lines) + "\n"


with open(os.path.join(OUT, "complex_artwork.svg"), "w") as f:
    f.write(make_svg())
with open(os.path.join(OUT, "complex_plate.dxf"), "w") as f:
    f.write(make_dxf())
with open(os.path.join(OUT, "terrain_mesh.stl"), "w") as f:
    f.write(make_stl())

print("testpack files written:")
for name in sorted(os.listdir(OUT)):
    path = os.path.join(OUT, name)
    if os.path.isfile(path):
        print(f"  {name}: {os.path.getsize(path):,} bytes")

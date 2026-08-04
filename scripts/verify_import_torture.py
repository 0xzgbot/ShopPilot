#!/usr/bin/env python3
"""R-NEXT-1: permanent verifier for the import-torture fixtures.

Asserts the defect class each fixture in docs/planning/research/import_torture/
claims in its README (open vectors, duplicates, self-intersections, zero-length
spans, overlaps, unit metadata, SVG structure). Stdlib-only. Reproducible.

Run:
    python3 scripts/verify_import_torture.py                  # repo-relative default
    python3 scripts/verify_import_torture.py --dir <path>     # explicit fixtures dir
    python3 scripts/verify_import_torture.py --list           # list checks only

Exit code 0 = all checks pass; 1 = any failure. Mirrors the 28-check ad-hoc
pass that validated these fixtures (see import_torture/README.md).
"""
import argparse
import os
import sys
import xml.etree.ElementTree as ET

# Fixture directory resolution: script lives in <repo>/scripts/.
DEFAULT_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                 "docs", "planning", "research", "import_torture")
)

FAILURES = []
TOTAL = {"n": 0}


def check(name, cond, detail=""):
    """Record one assertion. Always prints; collects failures."""
    TOTAL["n"] += 1
    tag = "ok  " if cond else "FAIL"
    print(f"  {tag} {name}" + (f" {detail}" if detail else ""))
    if not cond:
        FAILURES.append(name)


# --------------------------------------------------------------------------
# DXF parsing (ASCII R12 subset used by the fixtures)
# --------------------------------------------------------------------------

def parse_dxf(path):
    """Parse ASCII DXF pair list. Returns (entities, header).

    entities: list of [type, {code: [values...]}] — repeated codes preserved
              as lists (LWPOLYLINE vertices use repeated 10/20).
    header:   dict of header vars we care about (e.g. {'$INSUNITS': '4'}).
    """
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    if len(lines) % 2 != 0:
        raise ValueError("odd pair count")
    pairs = []
    for i in range(0, len(lines), 2):
        pairs.append((lines[i].strip(), lines[i + 1].strip()))

    entities, header = [], {}
    in_ents = in_hdr = awaiting_section = False
    hdr_name = None
    for code, val in pairs:
        if awaiting_section:
            if code == "2":
                in_ents = (val == "ENTITIES")
                in_hdr = (val == "HEADER")
                awaiting_section = False
            continue
        if code == "0":
            if val == "SECTION":
                in_ents = in_hdr = False
                awaiting_section = True
                continue
            if val in ("ENDSEC", "EOF"):
                in_ents = in_hdr = False
                continue
            if in_ents:
                entities.append([val, {}])
                continue
        if in_ents and entities:
            entities[-1][1].setdefault(code, []).append(val)
            continue
        if in_hdr:
            if code == "9":
                hdr_name = val
            elif hdr_name == "$INSUNITS" and code == "70":
                header["$INSUNITS"] = val
    return entities, header


def expand_attrs(entity):
    """Expand repeated 10/20 lists into 10_0,20_0,... keys (single vals kept)."""
    merged = {}
    for code, vals in entity[1].items():
        if code in ("10", "20") and isinstance(vals, list):
            for i, v in enumerate(vals):
                merged[f"{code}_{i}"] = v
        elif isinstance(vals, list):
            merged[code] = vals[0]
        else:
            merged[code] = vals
    return merged


def poly_vertices(entity):
    attrs = expand_attrs(entity)
    n = int(attrs.get("90", "0"))
    verts = []
    for i in range(n):
        verts.append((float(attrs[f"10_{i}"]), float(attrs[f"20_{i}"])))
    return verts, attrs.get("70", "0")


def circle(entity):
    a = expand_attrs(entity)
    return (float(a["10_0"]), float(a["20_0"]), float(a["40"]))


def dist(a, b):
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5


def segs_cross(p1, p2, p3, p4):
    """Proper segment intersection (excludes shared endpoints)."""
    def ccw(a, b, c):
        return (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0])
    d1, d2 = ccw(p3, p4, p1), ccw(p3, p4, p2)
    d3, d4 = ccw(p1, p2, p3), ccw(p1, p2, p4)
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0))


def self_intersections(verts):
    n = len(verts)
    count = 0
    for i in range(n - 1):
        for j in range(i + 2, n - 1):
            if i == 0 and j == n - 2:
                continue  # skip seam pair (closing edge shares start vertex)
            if segs_cross(verts[i], verts[i + 1], verts[j], verts[j + 1]):
                count += 1
    return count


# --------------------------------------------------------------------------
# Per-fixture checks (mirrors import_torture/README.md claims)
# --------------------------------------------------------------------------

def verify_dxf(fname, path):
    try:
        ents, hdr = parse_dxf(path)
    except Exception as e:  # malformed file
        check(fname, False, f"parse error: {e}")
        return

    if fname == "open_gap.dxf":
        check(f"{fname} entity count 1", len(ents) == 1, f"({len(ents)})")
        verts, closed = poly_vertices(ents[0])
        check(f"{fname} flag open", closed == "0")
        gap = dist(verts[-1], verts[0])
        check(f"{fname} geometric gap ~14.14", abs(gap - 14.142) < 0.01, f"gap={gap:.3f}")
    elif fname == "open_tiny_gap.dxf":
        verts, _ = poly_vertices(ents[0])
        gap = dist(verts[-1], verts[0])
        check(f"{fname} gap in [1e-6, 1e-3]", 1e-6 < gap <= 1e-3, f"gap={gap:.6f}")
    elif fname == "duplicate.dxf":
        check(f"{fname} entity count 2", len(ents) == 2, f"({len(ents)})")
        c1, c2 = circle(ents[0]), circle(ents[1])
        check(f"{fname} identical circles", c1 == c2, f"{c1} vs {c2}")
    elif fname == "duplicate_offset.dxf":
        c1, c2 = circle(ents[0]), circle(ents[1])
        d = dist(c1[:2], c2[:2])
        check(f"{fname} not identical", d > 1e-6, f"offset={d}")
        check(f"{fname} overlapping (d < r1+r2)", d < c1[2] + c2[2])
    elif fname == "self_intersect.dxf":
        verts, _ = poly_vertices(ents[0])
        check(f"{fname} vertex count matches 90", len(verts) == int(expand_attrs(ents[0])["90"]),
              f"({len(verts)})")
        check(f"{fname} has crossing", self_intersections(verts) >= 1,
              f"crossings={self_intersections(verts)}")
    elif fname == "zero_span.dxf":
        verts, _ = poly_vertices(ents[0])
        dup = any(dist(verts[i], verts[i + 1]) < 1e-9 for i in range(len(verts) - 1))
        check(f"{fname} duplicate consecutive vertex", dup)
    elif fname == "overlaps.dxf":
        r1 = expand_attrs(ents[0])
        r2 = expand_attrs(ents[1])
        x0 = max(float(r1["10_0"]), float(r2["10_0"]))
        y0 = max(float(r1["20_0"]), float(r2["20_0"]))
        x1 = min(float(r1["10_2"]), float(r2["10_2"]))
        y1 = min(float(r1["20_2"]), float(r2["20_2"]))
        area = max(0.0, x1 - x0) * max(0.0, y1 - y0)
        check(f"{fname} overlap area > 0", area > 0, f"area={area}")
    elif fname == "text_as_curves_open.dxf":
        verts, closed = poly_vertices(ents[0])
        check(f"{fname} flag open", closed == "0")
        check(f"{fname} geometrically open", dist(verts[-1], verts[0]) > 1e-3,
              f"gap={dist(verts[-1], verts[0]):.3f}")
    elif fname == "nested.dxf":
        c1, c2 = circle(ents[0]), circle(ents[1])
        contained = dist(c1[:2], c2[:2]) + c1[2] <= c2[2]
        check(f"{fname} inner circle contained (clean)", contained)
    elif fname == "fusion_units.dxf":
        check(f"{fname} INSUNITS=4 (mm)", hdr.get("$INSUNITS") == "4",
              f"({hdr.get('$INSUNITS')})")
        verts, _ = poly_vertices(ents[0])
        check(f"{fname} 25.4 square",
              abs(verts[1][0] - 25.4) < 1e-9 and abs(verts[2][1] - 25.4) < 1e-9)


def verify_svg(fname, path):
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        check(fname, False, f"XML parse error: {e}")
        return
    ns = {"svg": "http://www.w3.org/2000/svg"}
    paths = root.findall(".//svg:path", ns)
    circles = root.findall(".//svg:circle", ns)
    rects = root.findall(".//svg:rect", ns)
    groups = root.findall(".//svg:g", ns)
    if fname == "inkscape_style.svg":
        check(f"{fname} well-formed XML", True)
        check(f"{fname} 2 paths", len(paths) == 2, f"({len(paths)})")
        check(f"{fname} 1 circle", len(circles) == 1)
        check(f"{fname} 2 rects (dupe pair)", len(rects) == 2)
        check(f"{fname} 2 groups (transforms)", len(groups) == 2)
        check(f"{fname} mm width attr", root.get("width") == "100mm")
    else:  # illustrator_arc.svg
        check(f"{fname} well-formed XML", True)
        check(f"{fname} 3 paths", len(paths) == 3, f"({len(paths)})")
        check(f"{fname} one closed (Z)", any("Z" in (p.get("d") or "") for p in paths))
        check(f"{fname} one open", any("Z" not in (p.get("d") or "") for p in paths))
        check(f"{fname} beziers present", all("C" in (p.get("d") or "") for p in paths))


def main():
    ap = argparse.ArgumentParser(description="Verify import-torture fixtures.")
    ap.add_argument("--dir", default=DEFAULT_DIR, help="fixtures directory")
    ap.add_argument("--list", action="store_true", help="list checks without running")
    args = ap.parse_args()

    if not os.path.isdir(args.dir):
        print(f"ERROR: fixtures dir not found: {args.dir}")
        sys.exit(1)

    dxfs = sorted(f for f in os.listdir(args.dir) if f.endswith(".dxf"))
    svgs = sorted(f for f in os.listdir(args.dir) if f.endswith(".svg"))
    if args.list:
        print("DXF fixtures:", ", ".join(dxfs))
        print("SVG fixtures:", ", ".join(svgs))
        return

    print(f"Verifying import-torture fixtures in {args.dir}")
    print("== DXF ==")
    for f in dxfs:
        print(f"{f}:")
        verify_dxf(f, os.path.join(args.dir, f))
    print("== SVG ==")
    for f in svgs:
        print(f"{f}:")
        verify_svg(f, os.path.join(args.dir, f))

    print(f"\nRESULT: {TOTAL['n']} checks, {len(FAILURES)} failures")
    if FAILURES:
        print("FAILED:", ", ".join(FAILURES))
        sys.exit(1)
    print("PASS")


if __name__ == "__main__":
    main()
